package opencodehx.session;

import opencodehx.config.ConfigInfo;
import opencodehx.externs.node.Os;
import opencodehx.file.AppFileSystem;
import opencodehx.host.node.GlobalPaths;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;

typedef SessionInstructionContext = {
	final directory:String;
	final worktree:String;
	@:optional final config:ConfigInfo;
}

typedef NearbyInstructionInput = {
	final directory:String;
	final worktree:String;
	final filepath:String;
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
 * instructions, and local `config.instructions` entries. Per-message nearby
 * read-tool claims and remote instruction URL fetching are later session slices.
 */
class SessionInstruction {
	static final PROJECT_FILES:Array<String> = ["AGENTS.md", "CLAUDE.md", "CONTEXT.md"];

	public static function system(input:SessionInstructionContext):Array<String> {
		return [
			for (file in systemFiles(input))
				'Instructions from: ${file.filepath}\n${file.content}'
		];
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
			if (filepath == target || system.indexOf(filepath) != -1) {
				current = NodePath.dirname(current);
				continue;
			}
			final content = StringTools.trim(AppFileSystem.readFileString(filepath));
			if (content != "")
				out.push({filepath: filepath, content: 'Instructions from: ${filepath}\n${content}'});
			current = NodePath.dirname(current);
		}
		return out;
	}

	static function projectFiles():Array<String> {
		return claudePromptDisabled() ? ["AGENTS.md", "CONTEXT.md"] : PROJECT_FILES.copy();
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
