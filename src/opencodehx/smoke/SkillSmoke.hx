package opencodehx.smoke;

import genes.js.Async.await;
import haxe.DynamicAccess;
import haxe.Json;
import js.lib.Promise;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.AgentInfo;
import opencodehx.config.ConfigInfo.PermissionConfigValue;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.skill.SkillRemoteDiscovery.SkillFetchFunction;
import opencodehx.skill.SkillRemoteDiscovery.SkillFetchResponse;
import opencodehx.skill.SkillRemoteDiscovery.SkillIndexPayload;
import opencodehx.skill.SkillRegistry;
import opencodehx.skill.SkillRegistry.SkillInfo;

class SkillSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-skill-"));
		try {
			localOpencodeSkills(root);
			externalAndGlobalSkills(root);
			configSkillPaths(root);
			availableSkills(root);
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	@:async
	public static function runRemote():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-skill-remote-"));
		try {
			final fixture = directory(root, "fixture");
			final cache = directory(root, "cache");
			final baseUrl = "https://example.com/.well-known/skills/";
			write(fixture, "index.json", Json.stringify({
				skills: [
					{name: "remote-alpha", files: ["SKILL.md", "references/guide.md"]},
					{name: "remote-missing", files: ["README.md"]},
					{name: "remote-safe", files: ["SKILL.md", "../escape.md"]},
				]
			}));
			write(NodePath.join(fixture, "remote-alpha"), "SKILL.md", '---
name: remote-alpha
description: Alpha remote skill.
---

# Remote Alpha
');
			write(join(fixture, "remote-alpha", "references"), "guide.md", "# Guide\n");
			write(NodePath.join(fixture, "remote-missing"), "README.md", "# Missing Skill\n");
			write(NodePath.join(fixture, "remote-safe"), "SKILL.md", '---
name: remote-safe
description: Safe remote skill.
---

# Remote Safe
');

			var downloadCount = 0;
			final fetcher = skillFetcher(baseUrl, fixture, () -> downloadCount++);
			final config = new ConfigInfo();
			config.skills = {urls: [baseUrl.substr(0, baseUrl.length - 1)]};

			final discovery = @:await SkillRegistry.discoverWithRemote(root, cache, {
				home: root,
				worktree: root,
				config: config,
				fetcher: fetcher
			});
			eq(skillNames(discovery.skills), "remote-alpha,remote-safe", "remote skill discovery filters and sorts");
			eq(Fs.existsSync(join(cache, "remote-alpha", "references", "guide.md")), true, "remote skill reference downloaded");
			eq(Fs.existsSync(NodePath.join(cache, "escape.md")), false, "remote skill cache path stays contained");
			final firstCount = downloadCount;
			eq(firstCount > 0, true, "remote skill initial download count");

			final second = @:await SkillRegistry.discoverWithRemote(root, cache, {
				home: root,
				worktree: root,
				config: config,
				fetcher: fetcher
			});
			eq(skillNames(second.skills), "remote-alpha,remote-safe", "remote skill cache second discovery");
			eq(downloadCount, firstCount, "remote skill files reused from cache");
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function localOpencodeSkills(root:String):Void {
		final project = directory(root, "local-opencode");
		write(join(project, ".opencode", "skill", "test-skill"), "SKILL.md", '---
name: test-skill
description: A test skill for verification.
---

# Test Skill

Instructions here.
');
		write(join(project, ".opencode", "skill", "no-frontmatter"), "SKILL.md", "# No Frontmatter\n\nJust content.");
		write(join(project, ".opencode", "skills", "second-skill"), "SKILL.md", '---
name: second-skill
description: Second test skill.
---

# Skill Two
');

		final discovery = SkillRegistry.discover(project, {home: project, worktree: project});
		eq(discovery.skills.length, 2, "local skill count");
		final testSkill = require(SkillRegistry.get(discovery, "test-skill"), "test skill");
		eq(testSkill.description, "A test skill for verification.", "local skill description");
		contains(testSkill.location, join("skill", "test-skill", "SKILL.md"), "local skill location");
		eq(discovery.dirs.length, 3, "skill dirs include discovered skill files");

		final formatted = SkillRegistry.format(discovery.skills, true);
		final first = formatted.indexOf("<name>second-skill</name>");
		final second = formatted.indexOf("<name>test-skill</name>");
		eq(first > -1 && second > first, true, "verbose skill format sorted");
		contains(formatted, "file://", "verbose skill location file url");
	}

	static function externalAndGlobalSkills(root:String):Void {
		final worktree = directory(root, "external-skills");
		final project = directory(worktree, "project");
		write(join(project, ".claude", "skills", "claude-skill"), "SKILL.md", '---
name: claude-skill
description: A skill in the .claude skills directory.
---

# Claude Skill
');
		write(join(project, ".agents", "skills", "agent-skill"), "SKILL.md", '---
name: agent-skill
description: A skill in the .agents skills directory.
---

# Agent Skill
');
		write(join(worktree, ".claude", "skills", "root-skill"), "SKILL.md", '---
name: root-skill
description: A skill from an ancestor directory.
---

# Root Skill
');
		write(join(worktree, ".agents", "skills", "global-agent-skill"), "SKILL.md", '---
name: global-agent-skill
description: A global agent skill.
---

# Global Agent Skill
');

		final discovery = SkillRegistry.discover(project, {home: worktree, worktree: worktree});
		eq(discovery.skills.length, 4, "external skill count");
		eq(SkillRegistry.get(discovery, "claude-skill") != null, true, "project claude skill");
		eq(SkillRegistry.get(discovery, "agent-skill") != null, true, "project agents skill");
		eq(SkillRegistry.get(discovery, "root-skill") != null, true, "ancestor claude skill");
		eq(SkillRegistry.get(discovery, "global-agent-skill") != null, true, "home agents skill");

		final disabled = SkillRegistry.discover(project, {home: worktree, worktree: worktree, disableExternal: true});
		eq(disabled.skills.length, 0, "external skills disabled");
	}

	static function configSkillPaths(root:String):Void {
		final project = directory(root, "config-skill-paths");
		final extra = directory(root, "extra-skills");
		write(NodePath.join(extra, "path-skill"), "SKILL.md", '---
name: path-skill
description: A skill from skills.paths.
---

# Path Skill
');
		final config = new ConfigInfo();
		config.skills = {paths: [extra], urls: ["https://example.com/.well-known/skills/"]};

		final discovery = SkillRegistry.discover(project, {home: project, worktree: project, config: config});
		eq(discovery.skills.length, 1, "skills.paths count");
		eq(require(SkillRegistry.get(discovery, "path-skill"), "path skill").description, "A skill from skills.paths.", "skills.paths description");
	}

	static function availableSkills(root:String):Void {
		final project = directory(root, "available-skills");
		write(join(project, ".opencode", "skill", "alpha"), "SKILL.md", '---
name: alpha
description: Alpha skill.
---

# Alpha
');
		write(join(project, ".opencode", "skill", "beta"), "SKILL.md", '---
name: beta
description: Beta skill.
---

# Beta
');
		write(join(project, ".opencode", "skill", "gamma"), "SKILL.md", '---
name: gamma
description: Gamma skill.
---

# Gamma
');

		final discovery = SkillRegistry.discover(project, {home: project, worktree: project});
		eq(skillNames(SkillRegistry.available(discovery)), "alpha,beta,gamma", "available skills sorted without agent");

		final exact = agentWithSkillPermission("exact", skillPatternPermission([{pattern: "beta", action: "deny"}]));
		eq(skillNames(SkillRegistry.available(discovery, exact)), "alpha,gamma", "available skills exact deny");

		final wildcardThenSpecific = agentWithSkillPermission("wildcard",
			skillPatternPermission([{pattern: "*", action: "deny"}, {pattern: "gamma", action: "allow"},]));
		eq(skillNames(SkillRegistry.available(discovery, wildcardThenSpecific)), "gamma", "available skills specific allow overrides wildcard deny");

		final allDenied = agentWithSkillPermission("all-denied", "deny");
		eq(SkillRegistry.available(discovery, allDenied).length, 0, "available skills all denied");
	}

	static function agentWithSkillPermission(name:String, value:PermissionConfigValue):AgentInfo {
		final permission = new DynamicAccess<PermissionConfigValue>();
		permission.set("skill", value);
		return {name: name, permission: permission};
	}

	static function skillPatternPermission(entries:Array<{final pattern:String; final action:String;}>):PermissionConfigValue {
		final patterns = new DynamicAccess<String>();
		for (entry in entries)
			patterns.set(entry.pattern, entry.action);
		return cast patterns;
	}

	static function skillNames(skills:Array<SkillInfo>):String {
		return [for (skill in skills) skill.name].join(",");
	}

	static function skillFetcher(baseUrl:String, fixture:String, countDownload:() -> Void):SkillFetchFunction {
		return function(url:String):Promise<SkillFetchResponse> {
			if (!StringTools.startsWith(url, baseUrl))
				return Promise.resolve(skillResponse(404, "Not Found"));
			final relative = url.substr(baseUrl.length);
			final file = NodePath.join(fixture, relative);
			if (!Fs.existsSync(file))
				return Promise.resolve(skillResponse(404, "Not Found"));
			if (!StringTools.endsWith(relative, "index.json"))
				countDownload();
			return Promise.resolve(skillResponse(200, Fs.readFileSync(file, "utf8")));
		};
	}

	static function skillResponse(status:Int, body:String):SkillFetchResponse {
		return {
			ok: status >= 200 && status < 300,
			status: status,
			text: function():Promise<String> {
				return Promise.resolve(body);
			},
			json: function():Promise<SkillIndexPayload> {
				// Test fetch boundary: the production puller validates the index shape
				// before using it, while this fake response mirrors Response.json().
				final parsed:SkillIndexPayload = cast Json.parse(body);
				return Promise.resolve(parsed);
			},
		};
	}

	static function directory(root:String, name:String):String {
		final dir = NodePath.join(root, name);
		Fs.mkdirSync(dir, {recursive: true});
		return dir;
	}

	static function write(dir:String, name:String, data:String):Void {
		Fs.mkdirSync(dir, {recursive: true});
		Fs.writeFileSync(NodePath.join(dir, name), data);
	}

	static function join(first:String, second:String, third:String, ?fourth:String):String {
		final base = NodePath.join(NodePath.join(first, second), third);
		return fourth == null ? base : NodePath.join(base, fourth);
	}

	static function require<T>(value:Null<T>, label:String):T {
		if (value == null)
			throw '${label}: expected value';
		return value;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}

	static function contains(text:String, needle:String, label:String):Void {
		if (text.indexOf(needle) == -1)
			throw '$label: expected to contain ${needle}';
	}
}
