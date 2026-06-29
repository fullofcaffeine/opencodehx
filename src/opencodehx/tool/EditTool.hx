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
import opencodehx.tool.ToolTypes.ToolPermissionMetadata;
import opencodehx.tool.ToolTypes.ToolResultMetadata;

typedef EditToolInput = {
	final filePath:String;
	final oldString:String;
	final newString:String;
	final replaceAll:Null<Bool>;
}

class EditTool {
	public static function define():ToolDef {
		return ToolDefinition.typed(KnownToolID.Edit, "Replace text in a file or create a file when oldString is empty.", {
			parameters: [
				{
					name: "filePath",
					type: "string",
					required: true,
					description: "File path to modify"
				},
				{
					name: "oldString",
					type: "string",
					required: true,
					description: "Text to replace"
				},
				{
					name: "newString",
					type: "string",
					required: true,
					description: "Replacement text"
				},
				{
					name: "replaceAll",
					type: "boolean",
					required: false,
					description: "Replace every occurrence"
				},
			],
		}, decode, execute);
	}

	static function decode(raw:ToolCallInput):ToolInputDecode<EditToolInput> {
		final issues:Array<String> = [];
		final args = ToolValidation.record(raw.unknown(), issues);
		if (args == null)
			return Invalid(issues);
		final rawPath = ToolValidation.requireString(args, "filePath", issues);
		final oldString = ToolValidation.requireStringAllowEmpty(args, "oldString", issues);
		final newString = ToolValidation.requireStringAllowEmpty(args, "newString", issues);
		final replaceAllArg = ToolValidation.optionalBool(args, "replaceAll", issues);
		return ToolValidation.finish(issues, {
			filePath: rawPath,
			oldString: oldString,
			newString: newString,
			replaceAll: replaceAllArg
		});
	}

	static function execute(input:EditToolInput, ctx:ToolContext):ToolResult {
		if (input.oldString == input.newString)
			throw new ToolException(ExecutionFailed(KnownToolID.Edit, "No changes to apply: oldString and newString are identical."));

		final absolute = resolve(KnownToolID.Edit, ctx, input.filePath);
		final existed = Fs.existsSync(absolute);
		if (existed && Fs.statSync(absolute).isDirectory())
			throw new ToolException(ExecutionFailed(KnownToolID.Edit, 'Path is a directory, not a file: ${absolute}'));
		if (!existed && input.oldString != "")
			throw new ToolException(ExecutionFailed(KnownToolID.Edit, 'File ${absolute} not found'));

		final source = existed ? ToolBom.split(Fs.readFileSync(absolute, "utf8")) : ToolBom.split("");
		final oldContent = source.text;
		final ending = detectLineEnding(oldContent);
		final normalizedOld = convertToLineEnding(normalizeLineEndings(input.oldString), ending);
		final normalizedNew = convertToLineEnding(normalizeLineEndings(input.newString), ending);
		final replaceAll = input.replaceAll == null ? false : input.replaceAll;
		final next = input.oldString == "" ? ToolBom.split(normalizedNew) : ToolBom.split(replace(oldContent, normalizedOld, normalizedNew, replaceAll));
		final desiredBom = source.bom || next.bom;
		final nextContent = next.text;
		final diff = TextDiff.unified(absolute, oldContent, nextContent);
		final relative = ToolPaths.relative(ctx, absolute);
		ToolPermission.require(KnownToolID.Edit, ctx, {
			permission: "edit",
			patterns: [relative],
			always: ["*"],
			metadata: ToolPermissionMetadata.checked({filepath: absolute, diff: diff})
		});
		Fs.mkdirSync(NodePath.dirname(absolute), {recursive: true});
		Fs.writeFileSync(absolute, ToolBom.join(nextContent, desiredBom), "utf8");
		return {
			title: relative,
			metadata: ToolResultMetadata.checked({
				diff: diff,
				filediff: {
					file: absolute,
					patch: diff,
					additions: TextDiff.countAdditions(oldContent, nextContent),
					deletions: TextDiff.countDeletions(oldContent, nextContent),
				},
				diagnostics: {}
			}),
			output: "Edit applied successfully.",
		};
	}

	static function replace(content:String, oldString:String, newString:String, replaceAll:Bool):String {
		var notFound = true;
		for (search in replacementCandidates(content, oldString)) {
			final first = content.indexOf(search);
			if (first == -1)
				continue;
			notFound = false;
			if (replaceAll)
				return StringTools.replace(content, search, newString);
			final last = content.lastIndexOf(search);
			if (first != last)
				continue;
			return content.substr(0, first) + newString + content.substr(first + search.length);
		}
		if (notFound)
			throw new ToolException(ExecutionFailed(KnownToolID.Edit,
				"Could not find oldString in the file. It must match exactly, including whitespace, indentation, and line endings."));
		throw new ToolException(ExecutionFailed(KnownToolID.Edit,
			"Found multiple matches for oldString. Provide more surrounding context to make the match unique."));
	}

	static function replacementCandidates(content:String, find:String):Array<String> {
		final candidates:Array<String> = [];
		addCandidate(candidates, find);
		lineTrimmed(candidates, content, find);
		blockAnchor(candidates, content, find);
		whitespaceNormalized(candidates, content, find);
		indentationFlexible(candidates, content, find);
		escapeNormalized(candidates, content, find);
		trimmedBoundary(candidates, content, find);
		contextAware(candidates, content, find);
		multiOccurrence(candidates, content, find);
		return candidates;
	}

	static function lineTrimmed(out:Array<String>, content:String, find:String):Void {
		final original = content.split("\n");
		final search = trimTrailingEmpty(find.split("\n"));
		if (search.length == 0 || original.length < search.length)
			return;
		for (i in 0...(original.length - search.length + 1)) {
			var matches = true;
			for (j in 0...search.length) {
				if (StringTools.trim(original[i + j]) != StringTools.trim(search[j])) {
					matches = false;
					break;
				}
			}
			if (matches)
				addCandidate(out, linesBlock(original, i, i + search.length - 1));
		}
	}

	static function blockAnchor(out:Array<String>, content:String, find:String):Void {
		final original = content.split("\n");
		final search = trimTrailingEmpty(find.split("\n"));
		if (search.length < 3)
			return;
		final first = StringTools.trim(search[0]);
		final last = StringTools.trim(search[search.length - 1]);
		final candidates:Array<{start:Int, end:Int}> = [];
		for (i in 0...original.length) {
			if (StringTools.trim(original[i]) != first)
				continue;
			var j = i + 2;
			while (j < original.length) {
				if (StringTools.trim(original[j]) == last) {
					candidates.push({start: i, end: j});
					break;
				}
				j++;
			}
		}
		if (candidates.length == 0)
			return;
		if (candidates.length == 1) {
			final only = candidates[0];
			addCandidate(out, linesBlock(original, only.start, only.end));
			return;
		}
		var best:Null<{start:Int, end:Int}> = null;
		var bestScore = -1.0;
		for (candidate in candidates) {
			final score = blockSimilarity(original, search, candidate.start, candidate.end);
			if (score > bestScore) {
				bestScore = score;
				best = candidate;
			}
		}
		if (best != null && bestScore >= 0.3)
			addCandidate(out, linesBlock(original, best.start, best.end));
	}

	static function whitespaceNormalized(out:Array<String>, content:String, find:String):Void {
		final normalizedFind = normalizeWhitespace(find);
		if (normalizedFind == "")
			return;
		final lines = content.split("\n");
		for (line in lines) {
			final normalizedLine = normalizeWhitespace(line);
			if (normalizedLine == normalizedFind || normalizedLine.indexOf(normalizedFind) != -1)
				addCandidate(out, line);
		}
		final findLines = find.split("\n");
		if (findLines.length > 1 && lines.length >= findLines.length) {
			for (i in 0...(lines.length - findLines.length + 1)) {
				final block = lines.slice(i, i + findLines.length).join("\n");
				if (normalizeWhitespace(block) == normalizedFind)
					addCandidate(out, block);
			}
		}
	}

	static function indentationFlexible(out:Array<String>, content:String, find:String):Void {
		final normalizedFind = removeIndentation(find);
		final contentLines = content.split("\n");
		final findLines = find.split("\n");
		if (findLines.length == 0 || contentLines.length < findLines.length)
			return;
		for (i in 0...(contentLines.length - findLines.length + 1)) {
			final block = contentLines.slice(i, i + findLines.length).join("\n");
			if (removeIndentation(block) == normalizedFind)
				addCandidate(out, block);
		}
	}

	static function escapeNormalized(out:Array<String>, content:String, find:String):Void {
		final unescaped = unescapeSearch(find);
		if (content.indexOf(unescaped) != -1)
			addCandidate(out, unescaped);
		final lines = content.split("\n");
		final findLines = unescaped.split("\n");
		if (findLines.length == 0 || lines.length < findLines.length)
			return;
		for (i in 0...(lines.length - findLines.length + 1)) {
			final block = lines.slice(i, i + findLines.length).join("\n");
			if (unescapeSearch(block) == unescaped)
				addCandidate(out, block);
		}
	}

	static function trimmedBoundary(out:Array<String>, content:String, find:String):Void {
		final trimmed = StringTools.trim(find);
		if (trimmed == find)
			return;
		if (content.indexOf(trimmed) != -1)
			addCandidate(out, trimmed);
		final lines = content.split("\n");
		final findLines = find.split("\n");
		if (findLines.length == 0 || lines.length < findLines.length)
			return;
		for (i in 0...(lines.length - findLines.length + 1)) {
			final block = lines.slice(i, i + findLines.length).join("\n");
			if (StringTools.trim(block) == trimmed)
				addCandidate(out, block);
		}
	}

	static function contextAware(out:Array<String>, content:String, find:String):Void {
		final findLines = trimTrailingEmpty(find.split("\n"));
		if (findLines.length < 3)
			return;
		final contentLines = content.split("\n");
		final first = StringTools.trim(findLines[0]);
		final last = StringTools.trim(findLines[findLines.length - 1]);
		for (i in 0...contentLines.length) {
			if (StringTools.trim(contentLines[i]) != first)
				continue;
			var j = i + 2;
			while (j < contentLines.length) {
				if (StringTools.trim(contentLines[j]) == last) {
					final blockLines = contentLines.slice(i, j + 1);
					if (blockLines.length == findLines.length && middleSimilarityEnough(blockLines, findLines)) {
						addCandidate(out, blockLines.join("\n"));
						return;
					}
					break;
				}
				j++;
			}
		}
	}

	static function multiOccurrence(out:Array<String>, content:String, find:String):Void {
		var start = 0;
		while (true) {
			final index = content.indexOf(find, start);
			if (index == -1)
				break;
			addCandidate(out, find);
			start = index + find.length;
		}
	}

	static function addCandidate(out:Array<String>, value:String):Void {
		if (value == "")
			return;
		out.push(value);
	}

	static function trimTrailingEmpty(lines:Array<String>):Array<String> {
		final copy = lines.copy();
		if (copy.length > 0 && copy[copy.length - 1] == "")
			copy.pop();
		return copy;
	}

	static function linesBlock(lines:Array<String>, start:Int, end:Int):String {
		return lines.slice(start, end + 1).join("\n");
	}

	static function blockSimilarity(original:Array<String>, search:Array<String>, start:Int, end:Int):Float {
		final actualSize = end - start + 1;
		final linesToCheck = Std.int(Math.min(search.length - 2, actualSize - 2));
		if (linesToCheck <= 0)
			return 1.0;
		var similarity = 0.0;
		var j = 1;
		while (j < search.length - 1 && j < actualSize - 1) {
			final originalLine = StringTools.trim(original[start + j]);
			final searchLine = StringTools.trim(search[j]);
			final maxLen = Std.int(Math.max(originalLine.length, searchLine.length));
			if (maxLen > 0)
				similarity += 1 - levenshtein(originalLine, searchLine) / maxLen;
			j++;
		}
		return similarity / linesToCheck;
	}

	static function middleSimilarityEnough(blockLines:Array<String>, findLines:Array<String>):Bool {
		var matching = 0;
		var total = 0;
		for (i in 1...(blockLines.length - 1)) {
			final block = StringTools.trim(blockLines[i]);
			final find = StringTools.trim(findLines[i]);
			if (block.length > 0 || find.length > 0) {
				total++;
				if (block == find)
					matching++;
			}
		}
		return total == 0 || matching / total >= 0.5;
	}

	static function levenshtein(a:String, b:String):Int {
		if (a == "" || b == "")
			return Std.int(Math.max(a.length, b.length));
		final previous:Array<Int> = [];
		final current:Array<Int> = [];
		for (j in 0...(b.length + 1))
			previous.push(j);
		for (i in 1...(a.length + 1)) {
			current.splice(0, current.length);
			current.push(i);
			for (j in 1...(b.length + 1)) {
				final cost = a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1;
				current.push(Std.int(Math.min(Math.min(previous[j] + 1, current[j - 1] + 1), previous[j - 1] + cost)));
			}
			for (j in 0...current.length)
				previous[j] = current[j];
		}
		return previous[b.length];
	}

	static function normalizeWhitespace(text:String):String {
		final parts:Array<String> = [];
		var current = "";
		for (i in 0...text.length) {
			final ch = text.charAt(i);
			final code = text.charCodeAt(i);
			if (code <= 32) {
				if (current != "") {
					parts.push(current);
					current = "";
				}
			} else {
				current += ch;
			}
		}
		if (current != "")
			parts.push(current);
		return parts.join(" ");
	}

	static function removeIndentation(text:String):String {
		final lines = text.split("\n");
		var minIndent = 1073741824;
		for (line in lines) {
			if (StringTools.trim(line).length == 0)
				continue;
			minIndent = Std.int(Math.min(minIndent, indentation(line)));
		}
		if (minIndent == 1073741824 || minIndent == 0)
			return text;
		final out:Array<String> = [];
		for (line in lines)
			out.push(StringTools.trim(line).length == 0 ? line : line.substr(minIndent));
		return out.join("\n");
	}

	static function indentation(line:String):Int {
		var count = 0;
		while (count < line.length) {
			final code = line.charCodeAt(count);
			if (code != 32 && code != 9)
				break;
			count++;
		}
		return count;
	}

	static function unescapeSearch(text:String):String {
		var out = "";
		var i = 0;
		while (i < text.length) {
			final ch = text.charAt(i);
			if (ch == "\\" && i + 1 < text.length) {
				final next = text.charAt(i + 1);
				out += switch next {
					case "n": "\n";
					case "t": "\t";
					case "r": "\r";
					case "'" | '"' | "`" | "\\" | "$": next;
					default: "\\" + next;
				}
				i += 2;
			} else {
				out += ch;
				i++;
			}
		}
		return out;
	}

	static function normalizeLineEndings(text:String):String {
		return StringTools.replace(text, "\r\n", "\n");
	}

	static function detectLineEnding(text:String):String {
		return text.indexOf("\r\n") == -1 ? "\n" : "\r\n";
	}

	static function convertToLineEnding(text:String, ending:String):String {
		if (ending == "\n")
			return text;
		return StringTools.replace(text, "\n", "\r\n");
	}

	static function resolve(id:String, ctx:ToolContext, rawPath:String):String {
		try {
			return ToolPaths.resolve(ctx, rawPath);
		} catch (error:Dynamic) {
			throw new ToolException(ExecutionFailed(id, Std.string(error)));
		}
	}
}
