package opencodehx.skill;

import haxe.DynamicAccess;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.AgentInfo;
import opencodehx.config.ConfigMarkdown;
import opencodehx.config.ConfigMarkdown.MarkdownValue;
import opencodehx.config.ConfigMarkdownFiles;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodePath;
import opencodehx.permission.PermissionRules;

typedef SkillInfo = {
	final name:String;
	final description:String;
	final location:String;
	final content:String;
}

typedef SkillDiscoveryOptions = {
	@:optional final worktree:String;
	@:optional final home:String;
	@:optional final config:ConfigInfo;
	@:optional final configDirs:Array<String>;
	@:optional final disableExternal:Bool;
}

typedef SkillDiscovery = {
	final skills:Array<SkillInfo>;
	final dirs:Array<String>;
}

class SkillRegistry {
	public static function discover(directory:String, ?options:SkillDiscoveryOptions):SkillDiscovery {
		final opts:SkillDiscoveryOptions = options == null ? {} : options;
		final matches:Array<String> = [];
		final dirs:Array<String> = [];

		if (opts.disableExternal != true) {
			for (root in externalRoots(home(opts), directory, opts.worktree)) {
				scanSkillFiles(root, ["skills"], matches, dirs);
			}
		}

		var configDirs = opencodeDirectories(directory, opts.worktree);
		if (opts.configDirs != null)
			configDirs = opts.configDirs;
		for (dir in configDirs) {
			scanSkillFiles(dir, ["skill", "skills"], matches, dirs);
		}

		final cfg = opts.config;
		if (cfg != null && cfg.skills != null && cfg.skills.paths != null) {
			final paths:Array<String> = cfg.skills.paths;
			for (item in paths) {
				final root = resolveSkillPath(directory, home(opts), item);
				if (Fs.existsSync(root) && Fs.statSync(root).isDirectory())
					scanAnySkillFiles(root, matches, dirs);
			}
		}

		final byName = new DynamicAccess<SkillInfo>();
		for (match in unique(matches)) {
			final skill = load(match);
			if (skill != null)
				byName.set(skill.name, skill);
		}

		final skills:Array<SkillInfo> = [];
		for (name in byName.keys()) {
			final skill = byName.get(name);
			if (skill != null)
				skills.push(skill);
		}
		skills.sort((a, b) -> Reflect.compare(a.name, b.name));
		return {
			skills: skills,
			dirs: unique(dirs),
		};
	}

	public static function get(discovery:SkillDiscovery, name:String):Null<SkillInfo> {
		for (skill in discovery.skills) {
			if (skill.name == name)
				return skill;
		}
		return null;
	}

	public static function available(discovery:SkillDiscovery, ?agent:AgentInfo):Array<SkillInfo> {
		final sorted = discovery.skills.copy();
		sorted.sort((a, b) -> Reflect.compare(a.name, b.name));
		if (agent == null)
			return sorted;

		final ruleset = PermissionRules.fromConfig(agent.permission);
		final result:Array<SkillInfo> = [];
		for (skill in sorted) {
			final rule = PermissionRules.evaluate("skill", skill.name, [ruleset]);
			if (rule.action != "deny")
				result.push(skill);
		}
		return result;
	}

	public static function format(list:Array<SkillInfo>, verbose:Bool):String {
		if (list.length == 0)
			return "No skills are currently available.";
		final sorted = list.copy();
		sorted.sort((a, b) -> Reflect.compare(a.name, b.name));
		if (verbose) {
			final lines = ["<available_skills>"];
			for (skill in sorted) {
				lines.push("  <skill>");
				lines.push('    <name>${skill.name}</name>');
				lines.push('    <description>${skill.description}</description>');
				lines.push('    <location>${Url.pathToFileURL(skill.location).href}</location>');
				lines.push("  </skill>");
			}
			lines.push("</available_skills>");
			return lines.join("\n");
		}
		return "## Available Skills\n" + [for (skill in sorted) '- **${skill.name}**: ${skill.description}'].join("\n");
	}

	static function load(path:String):Null<SkillInfo> {
		final md = ConfigMarkdown.parse(path);
		final name = stringField(md.data, "name");
		final description = stringField(md.data, "description");
		if (name == null || description == null)
			return null;
		return {
			name: name,
			description: description,
			location: path,
			content: md.content,
		};
	}

	static function scanSkillFiles(root:String, roots:Array<String>, matches:Array<String>, dirs:Array<String>):Void {
		for (match in ConfigMarkdownFiles.scan(root, roots, true)) {
			if (NodePath.basename(match) == "SKILL.md") {
				matches.push(match);
				dirs.push(NodePath.dirname(match));
			}
		}
	}

	static function scanAnySkillFiles(root:String, matches:Array<String>, dirs:Array<String>):Void {
		for (match in ConfigMarkdownFiles.scan(root, [""], true)) {
			if (NodePath.basename(match) == "SKILL.md") {
				matches.push(match);
				dirs.push(NodePath.dirname(match));
			}
		}
	}

	static function externalRoots(home:String, directory:String, ?worktree:String):Array<String> {
		final result:Array<String> = [];
		for (base in [NodePath.join(home, ".claude"), NodePath.join(home, ".agents")]) {
			if (Fs.existsSync(base) && Fs.statSync(base).isDirectory())
				result.push(base);
		}
		for (dir in ancestors(directory, worktree)) {
			for (name in [".claude", ".agents"]) {
				final root = NodePath.join(dir, name);
				if (Fs.existsSync(root) && Fs.statSync(root).isDirectory())
					result.push(root);
			}
		}
		return unique(result);
	}

	static function opencodeDirectories(directory:String, ?worktree:String):Array<String> {
		final result:Array<String> = [];
		for (dir in ancestors(directory, worktree)) {
			final root = NodePath.join(dir, ".opencode");
			if (Fs.existsSync(root) && Fs.statSync(root).isDirectory())
				result.push(root);
		}
		return result;
	}

	static function ancestors(directory:String, ?worktree:String):Array<String> {
		final result:Array<String> = [];
		var current = NodePath.resolve(directory, "");
		final stop = worktree == null || worktree == "" ? null : NodePath.resolve(worktree, "");
		while (true) {
			result.push(current);
			if (stop != null && current == stop)
				break;
			final parent = NodePath.dirname(current);
			if (parent == current)
				break;
			current = parent;
		}
		result.reverse();
		return result;
	}

	static function resolveSkillPath(directory:String, home:String, path:String):String {
		if (StringTools.startsWith(path, "~/"))
			return NodePath.join(home, path.substr(2));
		if (NodePath.isAbsolute(path))
			return path;
		return NodePath.join(directory, path);
	}

	static function stringField(data:DynamicAccess<MarkdownValue>, field:String):Null<String> {
		final value = data.get(field);
		return Std.isOfType(value, String) ? cast value : null;
	}

	static function home(options:SkillDiscoveryOptions):String {
		return options.home != null ? options.home : Os.homedir();
	}

	static function unique(items:Array<String>):Array<String> {
		final seen:Map<String, Bool> = [];
		final result:Array<String> = [];
		for (item in items) {
			if (!seen.exists(item)) {
				seen.set(item, true);
				result.push(item);
			}
		}
		return result;
	}
}
