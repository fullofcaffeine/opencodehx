package opencodehx.patch;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.tool.TextDiff;

typedef PatchChunk = {
	final oldLines:Array<String>;
	final newLines:Array<String>;
	@:optional final changeContext:String;
	@:optional final isEndOfFile:Bool;
}

enum PatchHunk {
	AddFile(path:String, contents:String);
	DeleteFile(path:String);
	UpdateFile(path:String, movePath:Null<String>, chunks:Array<PatchChunk>);
}

typedef PatchParseResult = {
	final hunks:Array<PatchHunk>;
}

typedef ApplyPatchArgs = {
	final patch:String;
	final hunks:Array<PatchHunk>;
	@:optional final workdir:String;
}

enum MaybeApplyPatch {
	Body(args:ApplyPatchArgs);
	PatchParseError(message:String);
	NotApplyPatch;
}

enum PatchFileChange {
	AddChange(content:String);
	DeleteChange(content:String);
	UpdateChange(unifiedDiff:String, movePath:Null<String>, newContent:String);
}

typedef PatchActionChange = {
	final path:String;
	final change:PatchFileChange;
}

typedef ApplyPatchAction = {
	final changes:Array<PatchActionChange>;
	final patch:String;
	final cwd:String;
}

enum MaybeApplyPatchVerified {
	Body(action:ApplyPatchAction);
	CorrectnessError(message:String);
	NotApplyPatch;
}

typedef AffectedPaths = {
	final added:Array<String>;
	final modified:Array<String>;
	final deleted:Array<String>;
}

typedef PatchFileUpdate = {
	final unifiedDiff:String;
	final content:String;
	final bom:Bool;
}

class PatchRuntime {
	public static function parsePatch(patchText:String):PatchParseResult {
		final cleaned = stripHeredoc(StringTools.trim(StringTools.replace(patchText, "\r\n", "\n")));
		final lines = cleaned.split("\n");
		final beginIdx = indexOfLine(lines, "*** Begin Patch");
		final endIdx = indexOfLine(lines, "*** End Patch");
		if (beginIdx == -1 || endIdx == -1 || beginIdx >= endIdx)
			throw new haxe.Exception("Invalid patch format: missing Begin/End markers");

		final hunks:Array<PatchHunk> = [];
		var i = beginIdx + 1;
		while (i < endIdx) {
			final line = lines[i];
			if (StringTools.startsWith(line, "*** Add File:")) {
				final path = StringTools.trim(line.substr("*** Add File:".length));
				final parsed = parseAdd(lines, i + 1, endIdx);
				hunks.push(AddFile(path, parsed.content));
				i = parsed.next;
			} else if (StringTools.startsWith(line, "*** Delete File:")) {
				final path = StringTools.trim(line.substr("*** Delete File:".length));
				hunks.push(DeleteFile(path));
				i++;
			} else if (StringTools.startsWith(line, "*** Update File:")) {
				final path = StringTools.trim(line.substr("*** Update File:".length));
				var movePath:Null<String> = null;
				i++;
				if (i < endIdx && StringTools.startsWith(lines[i], "*** Move to:")) {
					movePath = StringTools.trim(lines[i].substr("*** Move to:".length));
					i++;
				}
				final parsed = parseChunks(lines, i, endIdx);
				hunks.push(UpdateFile(path, movePath, parsed.chunks));
				i = parsed.next;
			} else {
				i++;
			}
		}
		return {hunks: hunks};
	}

	public static function maybeParseApplyPatch(argv:Array<String>):MaybeApplyPatch {
		if (argv.length == 2 && isApplyPatchCommand(argv[0]))
			return parseBody(argv[1]);

		if (argv.length == 3 && argv[0] == "bash" && argv[1] == "-lc") {
			final patch = extractApplyPatchHeredoc(argv[2]);
			if (patch != null)
				return parseBody(patch);
		}

		return NotApplyPatch;
	}

	public static function deriveNewContentsFromChunks(filePath:String, chunks:Array<PatchChunk>):PatchFileUpdate {
		final oldContent = try {
			Fs.readFileSync(filePath, "utf8");
		} catch (error:Dynamic) {
			// Node filesystem calls can throw arbitrary JS-native values; convert
			// them immediately into the typed Haxe exception surface.
			throw new haxe.Exception('Failed to read file ${filePath}: ${Std.string(error)}');
		}
		final newContent = deriveNewContent(filePath, oldContent, chunks);
		return {
			unifiedDiff: TextDiff.unified(filePath, oldContent, newContent),
			content: newContent,
			bom: startsWithBom(oldContent)
		};
	}

	public static function applyHunksToFiles(hunks:Array<PatchHunk>):AffectedPaths {
		if (hunks.length == 0)
			throw new haxe.Exception("No files were modified.");

		final added:Array<String> = [];
		final modified:Array<String> = [];
		final deleted:Array<String> = [];

		for (hunk in hunks) {
			switch hunk {
				case AddFile(path, contents):
					writeText(path, contents);
					added.push(path);
				case DeleteFile(path):
					try {
						Fs.rmSync(path, {force: false});
					} catch (error:Dynamic) {
						// Node delete failures can be raw JS values; normalize them
						// at the patch runtime boundary.
						throw new haxe.Exception('Failed to delete file ${path}: ${Std.string(error)}');
					}
					deleted.push(path);
				case UpdateFile(path, movePath, chunks):
					final fileUpdate = deriveNewContentsFromChunks(path, chunks);
					if (movePath == null) {
						writeText(path, fileUpdate.content);
						modified.push(path);
					} else {
						final target = movePath;
						writeText(target, fileUpdate.content);
						Fs.rmSync(path, {force: false});
						modified.push(target);
					}
			}
		}

		return {added: added, modified: modified, deleted: deleted};
	}

	public static function applyPatch(patchText:String):AffectedPaths {
		return applyHunksToFiles(parsePatch(patchText).hunks);
	}

	public static function maybeParseApplyPatchVerified(argv:Array<String>, cwd:String):MaybeApplyPatchVerified {
		if (argv.length == 1) {
			try {
				parsePatch(argv[0]);
				return CorrectnessError("ImplicitInvocation");
			} catch (_:Dynamic) {
				// A failed parse here only means argv[0] is not an implicit patch;
				// command detection continues without exposing the raw JS value.
			}
		}

		return switch maybeParseApplyPatch(argv) {
			case Body(args):
				verifyBody(args, cwd);
			case PatchParseError(message):
				CorrectnessError(message);
			case NotApplyPatch:
				NotApplyPatch;
		}
	}

	private static function verifyBody(args:ApplyPatchArgs, cwd:String):MaybeApplyPatchVerified {
		final effectiveCwd = args.workdir == null ? cwd : NodePath.resolve(cwd, args.workdir);
		final changes:Array<PatchActionChange> = [];

		for (hunk in args.hunks) {
			switch hunk {
				case AddFile(path, contents):
					changes.push({
						path: NodePath.resolve(effectiveCwd, path),
						change: AddChange(contents)
					});
				case DeleteFile(path):
					final resolved = NodePath.resolve(effectiveCwd, path);
					try {
						changes.push({
							path: resolved,
							change: DeleteChange(Fs.readFileSync(resolved, "utf8"))
						});
					} catch (_:Dynamic) {
						// Node read failures are contained as verified-planning
						// correctness errors instead of escaping as raw JS values.
						return CorrectnessError('Failed to read file for deletion: ${resolved}');
					}
				case UpdateFile(path, movePath, chunks):
					final updatePath = NodePath.resolve(effectiveCwd, path);
					try {
						final fileUpdate = deriveNewContentsFromChunks(updatePath, chunks);
						final resolvedMove = movePath == null ? null : NodePath.resolve(effectiveCwd, movePath);
						changes.push({
							path: resolvedMove == null ? updatePath : resolvedMove,
							change: UpdateChange(fileUpdate.unifiedDiff, resolvedMove, fileUpdate.content)
						});
					} catch (error:Dynamic) {
						// Verification wraps parser/filesystem failures into the
						// typed MaybeApplyPatchVerified result.
						return CorrectnessError(Std.string(error));
					}
			}
		}

		return Body({
			changes: changes,
			patch: args.patch,
			cwd: effectiveCwd
		});
	}

	private static function parseBody(patch:String):MaybeApplyPatch {
		return try {
			Body({patch: patch, hunks: parsePatch(patch).hunks});
		} catch (error:Dynamic) {
			// maybeParse keeps parse errors as data so command detection callers
			// can distinguish patch syntax failures from non-patch commands.
			PatchParseError(Std.string(error));
		}
	}

	private static function isApplyPatchCommand(command:String):Bool {
		return command == "apply_patch" || command == "applypatch";
	}

	private static function extractApplyPatchHeredoc(script:String):Null<String> {
		final normalized = StringTools.replace(script, "\r\n", "\n");
		final lines = normalized.split("\n");
		if (lines.length < 3)
			return null;

		final first = StringTools.trim(lines[0]);
		if (!StringTools.startsWith(first, "apply_patch") || first.indexOf("<<") == -1)
			return null;

		final marker = heredocMarker(first);
		if (marker == null)
			return null;

		var end = 1;
		while (end < lines.length) {
			if (StringTools.trim(lines[end]) == marker)
				return lines.slice(1, end).join("\n");
			end++;
		}
		return null;
	}

	private static function heredocMarker(firstLine:String):Null<String> {
		final markerStart = firstLine.indexOf("<<");
		if (markerStart == -1)
			return null;
		final raw = StringTools.trim(firstLine.substr(markerStart + 2));
		if (raw == "")
			return null;
		final quote = raw.charAt(0);
		if (quote == "'" || quote == '"') {
			final closing = raw.indexOf(quote, 1);
			return closing == -1 ? raw.substr(1) : raw.substr(1, closing - 1);
		}
		final parts = raw.split(" ");
		return parts[0];
	}

	private static function parseAdd(lines:Array<String>, start:Int, endIdx:Int):{content:String, next:Int} {
		final content:Array<String> = [];
		var i = start;
		while (i < endIdx && !StringTools.startsWith(lines[i], "***")) {
			if (StringTools.startsWith(lines[i], "+"))
				content.push(lines[i].substr(1));
			i++;
		}
		return {content: content.join("\n"), next: i};
	}

	private static function parseChunks(lines:Array<String>, start:Int, endIdx:Int):{chunks:Array<PatchChunk>, next:Int} {
		final chunks:Array<PatchChunk> = [];
		var i = start;
		while (i < endIdx && !StringTools.startsWith(lines[i], "***")) {
			if (!StringTools.startsWith(lines[i], "@@")) {
				i++;
				continue;
			}
			final context = StringTools.trim(lines[i].substr(2));
			i++;
			final oldLines:Array<String> = [];
			final newLines:Array<String> = [];
			var eof = false;
			while (i < endIdx && !StringTools.startsWith(lines[i], "@@") && !StringTools.startsWith(lines[i], "***")) {
				final line = lines[i];
				if (line == "*** End of File") {
					eof = true;
					i++;
					break;
				}
				if (StringTools.startsWith(line, " ")) {
					final text = line.substr(1);
					oldLines.push(text);
					newLines.push(text);
				} else if (StringTools.startsWith(line, "-")) {
					oldLines.push(line.substr(1));
				} else if (StringTools.startsWith(line, "+")) {
					newLines.push(line.substr(1));
				}
				i++;
			}
			chunks.push({
				oldLines: oldLines,
				newLines: newLines,
				changeContext: context == "" ? null : context,
				isEndOfFile: eof
			});
		}
		return {chunks: chunks, next: i};
	}

	private static function deriveNewContent(filePath:String, oldContent:String, chunks:Array<PatchChunk>):String {
		final original = TextDiff.splitLines(oldContent);
		final replacements:Array<{start:Int, remove:Int, insert:Array<String>}> = [];
		var lineIndex = 0;
		for (chunk in chunks) {
			if (chunk.changeContext != null) {
				final contextText = Std.string(chunk.changeContext);
				final contextIdx = seekSequence(original, [contextText], lineIndex, false);
				if (contextIdx == -1)
					throw new haxe.Exception('Failed to find context ${contextText} in ${filePath}');
				lineIndex = contextIdx + 1;
			}
			if (chunk.oldLines.length == 0) {
				final insertion = original.length > 0 && original[original.length - 1] == "" ? original.length - 1 : original.length;
				replacements.push({start: insertion, remove: 0, insert: chunk.newLines});
				continue;
			}
			var found = seekSequence(original, chunk.oldLines, lineIndex, chunk.isEndOfFile == true);
			var oldPattern = chunk.oldLines;
			var newPattern = chunk.newLines;
			if (found == -1 && oldPattern.length > 0 && oldPattern[oldPattern.length - 1] == "") {
				oldPattern = oldPattern.slice(0, oldPattern.length - 1);
				if (newPattern.length > 0 && newPattern[newPattern.length - 1] == "")
					newPattern = newPattern.slice(0, newPattern.length - 1);
				found = seekSequence(original, oldPattern, lineIndex, chunk.isEndOfFile == true);
			}
			if (found == -1)
				throw new haxe.Exception('Failed to find expected lines in ${filePath}:\n${chunk.oldLines.join("\n")}');
			replacements.push({start: found, remove: oldPattern.length, insert: newPattern});
			lineIndex = found + oldPattern.length;
		}
		replacements.sort((a, b) -> Reflect.compare(a.start, b.start));
		final next = original.copy();
		var index = replacements.length - 1;
		while (index >= 0) {
			final replacement = replacements[index];
			next.splice(replacement.start, replacement.remove);
			for (i in 0...replacement.insert.length)
				next.insert(replacement.start + i, replacement.insert[i]);
			index--;
		}
		if (next.length == 0 || next[next.length - 1] != "")
			next.push("");
		return next.join("\n");
	}

	private static function seekSequence(lines:Array<String>, pattern:Array<String>, startIndex:Int, eof:Bool):Int {
		if (pattern.length == 0)
			return -1;
		final exact = tryMatch(lines, pattern, startIndex, eof, (a, b) -> a == b);
		if (exact != -1)
			return exact;
		final rstrip = tryMatch(lines, pattern, startIndex, eof, (a, b) -> rstrip(a) == rstrip(b));
		if (rstrip != -1)
			return rstrip;
		final trimmed = tryMatch(lines, pattern, startIndex, eof, (a, b) -> StringTools.trim(a) == StringTools.trim(b));
		if (trimmed != -1)
			return trimmed;
		return tryMatch(lines, pattern, startIndex, eof, (a, b) -> normalizeUnicode(StringTools.trim(a)) == normalizeUnicode(StringTools.trim(b)));
	}

	private static function tryMatch(lines:Array<String>, pattern:Array<String>, startIndex:Int, eof:Bool, compare:(String, String) -> Bool):Int {
		if (eof) {
			final fromEnd = lines.length - pattern.length;
			if (fromEnd >= startIndex && matchesAt(lines, pattern, fromEnd, compare))
				return fromEnd;
		}
		for (i in startIndex...(lines.length - pattern.length + 1)) {
			if (matchesAt(lines, pattern, i, compare))
				return i;
		}
		return -1;
	}

	private static function matchesAt(lines:Array<String>, pattern:Array<String>, start:Int, compare:(String, String) -> Bool):Bool {
		for (i in 0...pattern.length) {
			if (!compare(lines[start + i], pattern[i]))
				return false;
		}
		return true;
	}

	private static function rstrip(value:String):String {
		var end = value.length;
		while (end > 0) {
			final code = value.charCodeAt(end - 1);
			if (code != 32 && code != 9)
				break;
			end--;
		}
		return value.substr(0, end);
	}

	private static function normalizeUnicode(value:String):String {
		var out = value;
		for (quote in ["\u2018", "\u2019", "\u201A", "\u201B"])
			out = StringTools.replace(out, quote, "'");
		for (quote in ["\u201C", "\u201D", "\u201E", "\u201F"])
			out = StringTools.replace(out, quote, '"');
		for (dash in ["\u2010", "\u2011", "\u2012", "\u2013", "\u2014", "\u2015"])
			out = StringTools.replace(out, dash, "-");
		out = StringTools.replace(out, "\u2026", "...");
		out = StringTools.replace(out, "\u00A0", " ");
		return out;
	}

	private static function stripHeredoc(input:String):String {
		final lines = input.split("\n");
		if (lines.length < 3)
			return input;
		final first = StringTools.trim(lines[0]);
		if (first.indexOf("<<") == -1)
			return input;
		final marker = heredocMarker(first);
		if (marker == null)
			return input;
		if (StringTools.trim(lines[lines.length - 1]) != marker)
			return input;
		return lines.slice(1, lines.length - 1).join("\n");
	}

	private static function indexOfLine(lines:Array<String>, needle:String):Int {
		for (i in 0...lines.length) {
			if (StringTools.trim(lines[i]) == needle)
				return i;
		}
		return -1;
	}

	private static function writeText(path:String, content:String):Void {
		final dir = NodePath.dirname(path);
		try {
			if (dir != "." && dir != "/")
				Fs.mkdirSync(dir, {recursive: true});
			Fs.writeFileSync(path, content, "utf8");
		} catch (error:Dynamic) {
			// Host write failures are represented as patch failures immediately
			// so callers never need to inspect untyped Node exceptions.
			throw new haxe.Exception('Failed to write file ${path}: ${Std.string(error)}');
		}
	}

	private static function startsWithBom(content:String):Bool {
		return content.length > 0 && content.charCodeAt(0) == 0xfeff;
	}
}
