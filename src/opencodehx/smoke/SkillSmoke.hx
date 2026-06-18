package opencodehx.smoke;

import opencodehx.config.ConfigInfo;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.skill.SkillRegistry;

class SkillSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-skill-"));
		try {
			localOpencodeSkills(root);
			externalAndGlobalSkills(root);
			configSkillPaths(root);
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
