package opencodehx.tool;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.KnownToolID;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolInputDecode;
import opencodehx.tool.ToolTypes.ToolResult;

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

typedef PatchChange = {
	final type:String;
	final filePath:String;
	final relativePath:String;
	final oldContent:String;
	final newContent:String;
	final diff:String;
	final additions:Int;
	final deletions:Int;
	@:optional final movePath:String;
}

typedef ApplyPatchToolInput = {
	final patchText:String;
}

class ApplyPatchTool {
	public static function define():ToolDef {
		return ToolDefinition.typed(KnownToolID.ApplyPatch, "Apply an OpenAI-style patch envelope to project files.", {
			parameters: [
				{
					name: "patchText",
					type: "string",
					required: true,
					description: "Full patch text to apply"
				},
			],
		}, decode, execute);
	}

	static function decode(raw:ToolCallInput):ToolInputDecode<ApplyPatchToolInput> {
		final issues:Array<String> = [];
		final args = ToolValidation.record(raw.unknown(), issues);
		if (args == null)
			return Invalid(issues);
		final patchText = ToolValidation.requireString(args, "patchText", issues);
		return ToolValidation.finish(issues, {patchText: patchText});
	}

	static function execute(input:ApplyPatchToolInput, ctx:ToolContext):ToolResult {
		final hunks = parse(input.patchText);
		if (hunks.length == 0) {
			final normalized = StringTools.trim(StringTools.replace(StringTools.replace(input.patchText, "\r\n", "\n"), "\r", "\n"));
			if (normalized == "*** Begin Patch\n*** End Patch")
				throw new ToolException(ExecutionFailed(KnownToolID.ApplyPatch, "patch rejected: empty patch"));
			throw new ToolException(ExecutionFailed(KnownToolID.ApplyPatch, "apply_patch verification failed: no hunks found"));
		}

		final changes:Array<PatchChange> = [];
		for (hunk in hunks)
			changes.push(planChange(ctx, hunk));

		final diffLines:Array<String> = [];
		final patterns:Array<String> = [];
		for (change in changes) {
			diffLines.push(change.diff);
			patterns.push(change.relativePath);
		}
		final totalDiff = diffLines.join("\n");
		ToolPermission.require(KnownToolID.ApplyPatch, ctx, {
			permission: "edit",
			patterns: patterns,
			always: ["*"],
			metadata: {filepath: patterns.join(", "), diff: totalDiff, files: changes}
		});

		for (change in changes)
			applyChange(change);

		final summary:Array<String> = [];
		for (change in changes)
			summary.push(summaryLine(change));
		final output = 'Success. Updated the following files:\n${summary.join("\n")}';
		return {
			title: output,
			metadata: {diff: totalDiff, files: changes, diagnostics: {}},
			output: output,
		};
	}

	static function parse(patchText:String):Array<PatchHunk> {
		final cleaned = stripHeredoc(StringTools.trim(StringTools.replace(patchText, "\r\n", "\n")));
		final lines = cleaned.split("\n");
		final beginIdx = indexOfLine(lines, "*** Begin Patch");
		final endIdx = indexOfLine(lines, "*** End Patch");
		if (beginIdx == -1 || endIdx == -1 || beginIdx >= endIdx)
			throw new ToolException(ExecutionFailed(KnownToolID.ApplyPatch,
				"apply_patch verification failed: Invalid patch format: missing Begin/End markers"));

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
		return hunks;
	}

	static function parseAdd(lines:Array<String>, start:Int, endIdx:Int):{content:String, next:Int} {
		final content:Array<String> = [];
		var i = start;
		while (i < endIdx && !StringTools.startsWith(lines[i], "***")) {
			if (StringTools.startsWith(lines[i], "+"))
				content.push(lines[i].substr(1));
			i++;
		}
		return {content: content.join("\n"), next: i};
	}

	static function parseChunks(lines:Array<String>, start:Int, endIdx:Int):{chunks:Array<PatchChunk>, next:Int} {
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

	static function planChange(ctx:ToolContext, hunk:PatchHunk):PatchChange {
		return switch hunk {
			case AddFile(path, contents):
				final absolute = resolve(KnownToolID.ApplyPatch, ctx, path);
				final oldContent = "";
				final newContent = contents == "" || StringTools.endsWith(contents, "\n") ? contents : contents + "\n";
				makeChange(ctx, "add", absolute, null, oldContent, newContent);
			case DeleteFile(path):
				final absolute = resolve(KnownToolID.ApplyPatch, ctx, path);
				if (!Fs.existsSync(absolute) || !Fs.statSync(absolute).isFile())
					throw new ToolException(ExecutionFailed(KnownToolID.ApplyPatch,
						'apply_patch verification failed: Failed to read file to delete: ${absolute}'));
				makeChange(ctx, "delete", absolute, null, Fs.readFileSync(absolute, "utf8"), "");
			case UpdateFile(path, movePath, chunks):
				final absolute = resolve(KnownToolID.ApplyPatch, ctx, path);
				if (!Fs.existsSync(absolute) || !Fs.statSync(absolute).isFile())
					throw new ToolException(ExecutionFailed(KnownToolID.ApplyPatch,
						'apply_patch verification failed: Failed to read file to update: ${absolute}'));
				final oldContent = Fs.readFileSync(absolute, "utf8");
				final newContent = deriveNewContent(absolute, oldContent, chunks);
				final resolvedMove = movePath == null ? null : resolve(KnownToolID.ApplyPatch, ctx, movePath);
				makeChange(ctx, resolvedMove == null ? "update" : "move", absolute, resolvedMove, oldContent, newContent);
		}
	}

	static function makeChange(ctx:ToolContext, kind:String, filePath:String, movePath:Null<String>, oldContent:String, newContent:String):PatchChange {
		final target = movePath == null ? filePath : movePath;
		final relative = ToolPaths.relative(ctx, target);
		final diff = TextDiff.unified(filePath, oldContent, newContent);
		return {
			type: kind,
			filePath: filePath,
			relativePath: relative,
			oldContent: oldContent,
			newContent: newContent,
			diff: diff,
			additions: TextDiff.countAdditions(oldContent, newContent),
			deletions: TextDiff.countDeletions(oldContent, newContent),
			movePath: movePath
		};
	}

	static function applyChange(change:PatchChange):Void {
		switch change.type {
			case "add" | "update":
				Fs.mkdirSync(NodePath.dirname(change.filePath), {recursive: true});
				Fs.writeFileSync(change.filePath, change.newContent, "utf8");
			case "move":
				final target:Null<String> = change.movePath;
				if (target == null)
					throw new ToolException(ExecutionFailed(KnownToolID.ApplyPatch,
						'apply_patch verification failed: missing move target for ${change.filePath}'));
				Fs.mkdirSync(NodePath.dirname(target), {recursive: true});
				Fs.writeFileSync(target, change.newContent, "utf8");
				Fs.rmSync(change.filePath, {force: true});
			case "delete":
				Fs.rmSync(change.filePath, {force: true});
			case _:
		}
	}

	static function deriveNewContent(filePath:String, oldContent:String, chunks:Array<PatchChunk>):String {
		final original = TextDiff.splitLines(oldContent);
		final replacements:Array<{start:Int, remove:Int, insert:Array<String>}> = [];
		var lineIndex = 0;
		for (chunk in chunks) {
			if (chunk.changeContext != null) {
				final contextText = Std.string(chunk.changeContext);
				final contextIdx = seekSequence(original, [contextText], lineIndex, false);
				if (contextIdx == -1)
					throw new ToolException(ExecutionFailed(KnownToolID.ApplyPatch,
						'apply_patch verification failed: Failed to find context ${contextText} in ${filePath}'));
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
				throw new ToolException(ExecutionFailed(KnownToolID.ApplyPatch,
					'apply_patch verification failed: Failed to find expected lines in ${filePath}:\n${chunk.oldLines.join("\n")}'));
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

	static function seekSequence(lines:Array<String>, pattern:Array<String>, startIndex:Int, eof:Bool):Int {
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

	static function tryMatch(lines:Array<String>, pattern:Array<String>, startIndex:Int, eof:Bool, compare:(String, String) -> Bool):Int {
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

	static function summaryLine(change:PatchChange):String {
		if (change.type == "add")
			return 'A ${change.relativePath}';
		if (change.type == "delete")
			return 'D ${change.relativePath}';
		return 'M ${change.relativePath}';
	}

	static function matchesAt(lines:Array<String>, pattern:Array<String>, start:Int, compare:(String, String) -> Bool):Bool {
		for (i in 0...pattern.length) {
			if (!compare(lines[start + i], pattern[i]))
				return false;
		}
		return true;
	}

	static function rstrip(value:String):String {
		var end = value.length;
		while (end > 0) {
			final code = value.charCodeAt(end - 1);
			if (code != 32 && code != 9)
				break;
			end--;
		}
		return value.substr(0, end);
	}

	static function normalizeUnicode(value:String):String {
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

	static function stripHeredoc(input:String):String {
		final lines = input.split("\n");
		if (lines.length < 3)
			return input;
		final first = StringTools.trim(lines[0]);
		if (first.indexOf("<<") == -1)
			return input;
		final marker = first.substr(first.indexOf("<<") + 2).split(" ").join("");
		final cleaned = StringTools.replace(StringTools.replace(marker, "'", ""), '"', "");
		if (StringTools.trim(lines[lines.length - 1]) != cleaned)
			return input;
		return lines.slice(1, lines.length - 1).join("\n");
	}

	static function indexOfLine(lines:Array<String>, needle:String):Int {
		for (i in 0...lines.length) {
			if (StringTools.trim(lines[i]) == needle)
				return i;
		}
		return -1;
	}

	static function resolve(id:String, ctx:ToolContext, rawPath:String):String {
		try {
			return ToolPaths.resolve(ctx, rawPath);
		} catch (error:Dynamic) {
			throw new ToolException(ExecutionFailed(id, Std.string(error)));
		}
	}
}
