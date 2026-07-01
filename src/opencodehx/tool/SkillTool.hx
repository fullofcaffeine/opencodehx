package opencodehx.tool;

import genes.js.Async.await;
import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodePath;
import opencodehx.skill.SkillRegistry;
import opencodehx.skill.SkillRegistry.SkillDiscovery;
import opencodehx.skill.SkillRegistry.SkillInfo;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.KnownToolID;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolInputDecode;
import opencodehx.tool.ToolTypes.ToolPermissionMetadata;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolTypes.ToolResultMetadata;
import opencodehx.util.Compare.compareString;

typedef SkillToolInput = {
	final name:String;
}

/**
 * Executable facade for upstream `tool/skill`.
 *
 * The current builtin registry is synchronous, while upstream's skill tool is
 * Effect/stream-backed. Keep this facade beside the registry until async tool
 * execution is a first-class registry/session behavior.
 */
class SkillTool {
	public static function decode(raw:ToolCallInput):ToolInputDecode<SkillToolInput> {
		final issues:Array<String> = [];
		final args = ToolValidation.record(raw.unknown(), issues);
		if (args == null)
			return Invalid(issues);
		final name = ToolValidation.requireString(args, "name", issues);
		return ToolValidation.finish(issues, {name: name});
	}

	@:async
	public static function executeRaw(raw:ToolCallInput, ctx:ToolContext):Promise<ToolResult> {
		return switch decode(raw) {
			case Decoded(input):
				await(execute(input, ctx));
			case Invalid(issues):
				throw new ToolException(InvalidArguments(KnownToolID.Skill, issues));
		}
	}

	@:async
	public static function execute(input:SkillToolInput, ctx:ToolContext):Promise<ToolResult> {
		final discovery = discoveryFor(ctx);
		final info = SkillRegistry.get(discovery, input.name);
		if (info == null)
			throw new ToolException(ExecutionFailed(KnownToolID.Skill, notFoundMessage(input.name, discovery)));

		ToolPermission.require(KnownToolID.Skill, ctx, {
			permission: "skill",
			patterns: [input.name],
			always: [input.name],
			metadata: ToolPermissionMetadata.empty(),
		});

		final dir = NodePath.dirname(info.location);
		return {
			title: 'Loaded skill: ${info.name}',
			output: output(info, dir),
			metadata: ToolResultMetadata.checked({name: info.name, dir: dir}),
		};
	}

	static function discoveryFor(ctx:ToolContext):SkillDiscovery {
		final worktree = ctx.worktree == null || ctx.worktree == "" ? ctx.directory : ctx.worktree;
		return SkillRegistry.discover(ctx.directory, {
			home: ctx.directory,
			worktree: worktree,
		});
	}

	static function output(info:SkillInfo, dir:String):String {
		return [
			'<skill_content name="${info.name}">',
			'# Skill: ${info.name}',
			"",
			StringTools.trim(info.content),
			"",
			'Base directory for this skill: ${Url.pathToFileURL(dir).href}',
			"Relative paths in this skill (e.g., scripts/, reference/) are relative to this base directory.",
			"Note: file list is sampled.",
			"",
			"<skill_files>",
			fileList(dir, 10),
			"</skill_files>",
			"</skill_content>",
		].join("\n");
	}

	static function fileList(root:String, limit:Int):String {
		final files:Array<String> = [];
		collectFiles(root, limit, files);
		return [for (file in files) '<file>${file}</file>'].join("\n");
	}

	static function collectFiles(dir:String, limit:Int, files:Array<String>):Void {
		if (files.length >= limit)
			return;
		final entries = Fs.readdirNamesSync(dir);
		entries.sort(compareString);
		for (entry in entries) {
			if (files.length >= limit)
				return;
			final path = NodePath.join(dir, entry);
			if (path.indexOf("SKILL.md") != -1)
				continue;
			final stat = Fs.statSync(path);
			if (stat.isDirectory()) {
				collectFiles(path, limit, files);
			} else if (stat.isFile()) {
				files.push(NodePath.resolve(path, ""));
			}
		}
	}

	static function notFoundMessage(name:String, discovery:SkillDiscovery):String {
		final available = [for (skill in discovery.skills) skill.name].join(", ");
		return 'Skill "${name}" not found. Available skills: ${available == "" ? "none" : available}';
	}
}
