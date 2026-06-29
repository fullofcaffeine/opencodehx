package opencodehx.session;

import genes.ts.JsonValue;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import js.lib.Promise;
import opencodehx.config.ConfigInfo;
import opencodehx.externs.web.GlobalFetch;
import opencodehx.externs.node.Os;
import opencodehx.file.AppFileSystem;
import opencodehx.host.node.GlobalPaths;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.ToolState;
import opencodehx.session.MessageTypes.ToolStateMetadata;
import opencodehx.session.MessageTypes.WithParts;
import opencodehx.tool.ToolTypes.KnownToolID;
import opencodehx.util.Abort;

typedef SessionInstructionContext = {
	final directory:String;
	final worktree:String;
	@:optional final config:ConfigInfo;
}

typedef NearbyInstructionInput = {
	final directory:String;
	final worktree:String;
	final filepath:String;
	@:optional final messageID:String;
	@:optional final claims:SessionInstructionClaims;
	@:optional final previouslyLoaded:Array<String>;
}

typedef SessionInstructionFile = {
	final filepath:String;
	final content:String;
}

/**
 * System-level instruction discovery for live session prompts.
 *
 * This ports the deterministic file-backed subset of upstream
 * `session/instruction.ts`: project/root instruction files, global profile
 * instructions, local `config.instructions` entries, async remote instruction
 * URLs for live prompts, nearby read-tool instruction discovery with
 * per-assistant-message claim dedupe, and completed read-tool metadata
 * extraction from recovered Message V2 history.
 */
class SessionInstruction {
	static final PROJECT_FILES:Array<String> = ["AGENTS.md", "CLAUDE.md", "CONTEXT.md"];
	static inline final REMOTE_TIMEOUT_MS = 5000;

	public static function system(input:SessionInstructionContext):Array<String> {
		return [
			for (file in systemFiles(input))
				'Instructions from: ${file.filepath}\n${file.content}'
		];
	}

	@:async
	public static function systemAsync(input:SessionInstructionContext):Promise<Array<String>> {
		final out = system(input);
		final instructions = input.config == null ? null : input.config.instructions;
		if (instructions == null)
			return out;
		for (raw in instructions) {
			if (!isRemote(raw))
				continue;
			final content = StringTools.trim(@:await fetchRemote(raw));
			if (content != "")
				out.push('Instructions from: ${raw}\n${content}');
		}
		return out;
	}

	public static function systemFiles(input:SessionInstructionContext):Array<SessionInstructionFile> {
		final paths = systemPaths(input);
		final out:Array<SessionInstructionFile> = [];
		for (filepath in paths) {
			if (!AppFileSystem.isFile(filepath))
				continue;
			final content = StringTools.trim(AppFileSystem.readFileString(filepath));
			if (content != "")
				out.push({filepath: filepath, content: content});
		}
		return out;
	}

	public static function systemPaths(input:SessionInstructionContext):Array<String> {
		final paths:Array<String> = [];
		final stop = instructionStop(input.directory, input.worktree);
		if (!projectConfigDisabled()) {
			for (file in projectFiles()) {
				final matches = AppFileSystem.findUp(file, input.directory, stop);
				if (matches.length > 0) {
					addPath(paths, matches[0]);
					break;
				}
			}
		}

		for (file in globalFiles()) {
			if (AppFileSystem.isFile(file)) {
				addPath(paths, file);
				break;
			}
		}

		final instructions = input.config == null ? null : input.config.instructions;
		if (instructions != null) {
			for (raw in instructions) {
				if (isRemote(raw))
					continue;
				for (match in instructionMatches(raw, input.directory, stop))
					addPath(paths, match);
			}
		}
		return paths;
	}

	public static function nearbyForFile(input:NearbyInstructionInput):Array<SessionInstructionFile> {
		final system = systemPaths({
			directory: input.directory,
			worktree: input.worktree,
		});
		final previouslyLoaded:Array<String> = input.previouslyLoaded == null ? [] : input.previouslyLoaded;
		final out:Array<SessionInstructionFile> = [];
		final root = NodePath.resolve(input.directory, ".");
		final target = NodePath.resolve(input.filepath, ".");
		var current = NodePath.dirname(target);
		while (isWithin(root, current) && current != root) {
			final found = findInDirectory(current);
			if (found == null) {
				current = NodePath.dirname(current);
				continue;
			}
			final filepath:String = found;
			if (filepath == target || system.indexOf(filepath) != -1 || previouslyLoaded.indexOf(filepath) != -1) {
				current = NodePath.dirname(current);
				continue;
			}
			final claims = input.claims;
			final messageID = input.messageID;
			if (claims != null && messageID != null) {
				if (claims.has(messageID, filepath)) {
					current = NodePath.dirname(current);
					continue;
				}
				claims.claim(messageID, filepath);
			}
			final content = StringTools.trim(AppFileSystem.readFileString(filepath));
			if (content != "")
				out.push({filepath: filepath, content: 'Instructions from: ${filepath}\n${content}'});
			current = NodePath.dirname(current);
		}
		return out;
	}

	public static function loadedFromHistory(messages:Array<WithParts>):Array<String> {
		final out:Array<String> = [];
		for (message in messages) {
			for (part in message.parts) {
				switch part {
					case ToolPart(tool):
						if (tool.tool != KnownToolID.Read)
							continue;
						switch tool.state {
							case ToolCompleted(data):
								if (data.time.compacted != null)
									continue;
								addLoadedMetadata(out, data.metadata);
							case _:
						}
					case _:
				}
			}
		}
		return out;
	}

	static function projectFiles():Array<String> {
		return claudePromptDisabled() ? ["AGENTS.md", "CONTEXT.md"] : PROJECT_FILES.copy();
	}

	static function addLoadedMetadata(out:Array<String>, metadata:ToolStateMetadata):Void {
		final json:JsonValue = metadata;
		// Tool metadata is intentionally open JSON. This extractor narrows only
		// upstream's read-tool `metadata.loaded: string[]` field and returns
		// plain paths so JSON boundary access cannot leak into app logic.
		final record = UnknownNarrow.record(Unknown.fromBoundary(json));
		if (record == null)
			return;
		final loaded = UnknownNarrow.array(record.get("loaded"));
		if (loaded == null)
			return;
		for (index in 0...loaded.length) {
			final path = UnknownNarrow.string(loaded.get(index));
			if (path != null)
				addPath(out, path);
		}
	}

	static function globalFiles():Array<String> {
		final files:Array<String> = [];
		final configDir = NodeProcess.envValue("OPENCODE_CONFIG_DIR");
		if (configDir != null && configDir != "")
			files.push(NodePath.join(configDir, "AGENTS.md"));
		files.push(NodePath.join(GlobalPaths.config(NodeProcess.env()), "AGENTS.md"));
		if (!claudePromptDisabled())
			files.push(NodePath.join(NodePath.join(Os.homedir(), ".claude"), "CLAUDE.md"));
		return files;
	}

	static function findInDirectory(directory:String):Null<String> {
		for (file in projectFiles()) {
			final candidate = NodePath.resolve(NodePath.join(directory, file), ".");
			if (AppFileSystem.isFile(candidate))
				return candidate;
		}
		return null;
	}

	static function instructionMatches(raw:String, directory:String, worktree:String):Array<String> {
		final instruction = expandHome(raw);
		if (NodePath.isAbsolute(instruction)) {
			return AppFileSystem.glob(NodePath.basename(instruction), {
				cwd: NodePath.dirname(instruction),
				absolute: true,
			});
		}
		if (projectConfigDisabled()) {
			final configDir = NodeProcess.envValue("OPENCODE_CONFIG_DIR");
			if (configDir == null || configDir == "")
				return [];
			return AppFileSystem.globUp(instruction, configDir, configDir);
		}
		return AppFileSystem.globUp(instruction, directory, worktree);
	}

	static function instructionStop(directory:String, worktree:String):String {
		return worktree == "/" ? directory : worktree;
	}

	static function expandHome(path:String):String {
		return StringTools.startsWith(path, "~/") ? NodePath.join(Os.homedir(), path.substr(2)) : path;
	}

	static function isRemote(path:String):Bool {
		return StringTools.startsWith(path, "https://") || StringTools.startsWith(path, "http://");
	}

	@:async
	static function fetchRemote(url:String):Promise<String> {
		final timeout = Abort.abortAfter(REMOTE_TIMEOUT_MS);
		try {
			final response = @:await GlobalFetch.response(url, {signal: timeout.signal});
			timeout.clearTimeout();
			if (!response.ok)
				return "";
			return @:await response.text();
		} catch (_:haxe.Exception) {
			// Remote instruction fetch failures are intentionally treated like
			// absent instructions, matching upstream's prompt assembly behavior.
			timeout.clearTimeout();
			return "";
		}
	}

	static function addPath(paths:Array<String>, filepath:String):Void {
		final resolved = NodePath.resolve(filepath, ".");
		if (paths.indexOf(resolved) == -1)
			paths.push(resolved);
	}

	static function isWithin(root:String, target:String):Bool {
		return target == root || AppFileSystem.contains(root, target);
	}

	static function projectConfigDisabled():Bool {
		final value = NodeProcess.envValue("OPENCODE_DISABLE_PROJECT_CONFIG");
		return value == "true" || value == "1";
	}

	static function claudePromptDisabled():Bool {
		final value = NodeProcess.envValue("OPENCODE_DISABLE_CLAUDE_CODE_PROMPT");
		return value == "true" || value == "1";
	}
}
