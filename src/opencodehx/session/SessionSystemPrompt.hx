package opencodehx.session;

import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.AgentInfo;
import opencodehx.host.node.NodeProcess;
import opencodehx.project.ProjectRuntime;
import opencodehx.project.ProjectRuntime.ProjectVcs;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.permission.PermissionRules;
import opencodehx.resource.Resources;
import opencodehx.resource.Resources.ResourcePaths;
import opencodehx.skill.SkillRegistry;

typedef SessionSystemPromptInput = {
	final directory:String;
	final model:ProviderModel;
	@:optional final agent:AgentInfo;
	@:optional final config:ConfigInfo;
	@:optional final userSystem:String;
}

/**
 * Upstream-shaped system prompt assembly for live session runs.
 *
 * This module owns provider prompt selection, deterministic environment text,
 * available skill formatting, and final agent/provider composition. Plugin
 * system transforms and full prompt-loop reminders remain in later session
 * slices; callers receive plain strings that flow directly to AI SDK messages.
 */
class SessionSystemPrompt {
	public static function build(input:SessionSystemPromptInput):Array<String> {
		final discovery = ProjectRuntime.fromDirectory(input.directory);
		final project = discovery.project;
		final header = input.agent != null && hasText(input.agent.prompt) ? [StringTools.trim(input.agent.prompt)] : provider(input.model);
		final environmentPrompt = environment(input.model, input.directory, project.worktree, project.vcs == ProjectVcs.GitVcs);
		final skillsPrompt = skills(input.directory, project.worktree, input.config, input.agent);
		final parts = header.concat(environmentPrompt).concat(skillsPrompt);
		if (hasText(input.userSystem))
			parts.push(StringTools.trim(input.userSystem));
		return [parts.join("\n")];
	}

	public static function provider(model:ProviderModel):Array<String> {
		final apiID = model.api.id;
		final lower = apiID.toLowerCase();
		final promptPath = if (apiID.indexOf("gpt-4") != -1 || apiID.indexOf("o1") != -1 || apiID.indexOf("o3") != -1) {
			ResourcePaths.known("prompt/session/beast.txt");
		} else if (apiID.indexOf("gpt") != -1) {
			apiID.indexOf("codex") != -1 ? ResourcePaths.known("prompt/session/codex.txt") : ResourcePaths.known("prompt/session/gpt.txt");
		} else if (apiID.indexOf("gemini-") != -1) {
			ResourcePaths.known("prompt/session/gemini.txt");
		} else if (apiID.indexOf("claude") != -1) {
			ResourcePaths.known("prompt/session/anthropic.txt");
		} else if (lower.indexOf("trinity") != -1) {
			ResourcePaths.known("prompt/session/trinity.txt");
		} else if (lower.indexOf("kimi") != -1) {
			ResourcePaths.known("prompt/session/kimi.txt");
		} else {
			ResourcePaths.known("prompt/session/default.txt");
		}
		return [Resources.text(promptPath)];
	}

	public static function environment(model:ProviderModel, directory:String, worktree:String, isGit:Bool):Array<String> {
		return [
			[
				'You are powered by the model named ${model.api.id}. The exact model ID is ${model.providerID.toString()}/${model.api.id}',
				"Here is some useful information about the environment you are running in:",
				"<env>",
				'  Working directory: ${directory}',
				'  Workspace root folder: ${worktree}',
				'  Is directory a git repo: ${isGit ? "yes" : "no"}',
				'  Platform: ${NodeProcess.platform()}',
				"  Today's date: " + new js.lib.Date().toDateString(),
				"</env>",
			].join("\n")
		];
	}

	public static function skills(directory:String, worktree:String, config:Null<ConfigInfo>, agent:Null<AgentInfo>):Array<String> {
		if (agent != null && PermissionRules.disabled(["skill"], PermissionRules.fromConfig(agent.permission)).length > 0)
			return [];
		final discovery = SkillRegistry.discover(directory, {
			worktree: worktree,
			config: config,
		});
		final available = SkillRegistry.available(discovery, agent);
		if (available.length == 0)
			return [];
		return [
			[
				"Skills provide specialized instructions and workflows for specific tasks.",
				"Use the skill tool to load a skill when a task matches its description.",
				SkillRegistry.format(available, true),
			].join("\n")
		];
	}

	static function hasText(value:Null<String>):Bool {
		return value != null && StringTools.trim(value) != "";
	}
}
