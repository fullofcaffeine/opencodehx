package opencodehx.smoke;

import opencodehx.externs.node.Os;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.permission.BashArity;
import opencodehx.permission.PermissionRules;
import opencodehx.permission.PermissionRuntime;
import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolError.ToolFailure;
import opencodehx.tool.ToolRegistry;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolIDs;
import opencodehx.tool.ToolTypes.ToolPermissionMetadata;

class PermissionSmoke {
	public static function run():Void {
		fromConfigAndEvaluate();
		taskPermissionRules();
		bashArityPrefix();
		disabledTools();
		runtimeAskReply();
		toolIntegration();
	}

	static function bashArityPrefix():Void {
		eq(BashArity.prefix(["unknown", "command", "subcommand"]).join(" "), "unknown", "arity unknown command");
		eq(BashArity.prefix(["touch", "foo.txt"]).join(" "), "touch", "arity one token command");
		eq(BashArity.prefix(["git", "checkout", "main"]).join(" "), "git checkout", "arity two git");
		eq(BashArity.prefix(["docker", "run", "nginx"]).join(" "), "docker run", "arity two docker");
		eq(BashArity.prefix(["aws", "s3", "ls", "my-bucket"]).join(" "), "aws s3 ls", "arity three aws");
		eq(BashArity.prefix(["npm", "run", "dev", "script"]).join(" "), "npm run dev", "arity three npm run");
		eq(BashArity.prefix(["docker", "compose", "up", "service"]).join(" "), "docker compose up", "arity longest docker compose");
		eq(BashArity.prefix(["consul", "kv", "get", "config"]).join(" "), "consul kv get", "arity longest consul kv");
		eq(BashArity.prefix(["git", "checkout"]).join(" "), "git checkout", "arity exact git checkout");
		eq(BashArity.prefix(["npm", "run", "dev"]).join(" "), "npm run dev", "arity exact npm run dev");
		eq(BashArity.prefix([]).join(" "), "", "arity empty");
		eq(BashArity.prefix(["single"]).join(" "), "single", "arity single");
		eq(BashArity.prefix(["git"]).join(" "), "git", "arity short known command");
	}

	static function fromConfigAndEvaluate():Void {
		final rules = PermissionRules.fromConfig(cast {
			"*": "ask",
			bash: {"*": "allow", "rm *": "deny"},
			edit: "deny",
			external_directory: {"~/projects/*": "allow"},
		});
		eq(PermissionRules.evaluate("bash", "git status", [rules]).action, "allow", "bash allow");
		eq(PermissionRules.evaluate("bash", "rm -rf tmp", [rules]).action, "deny", "bash deny");
		eq(PermissionRules.evaluate("edit", "src/a.ts", [rules]).action, "deny", "edit deny");
		eq(PermissionRules.evaluate("read", "src/a.ts", [rules]).action, "ask", "wildcard fallback");
		eq(PermissionRules.evaluate("external_directory", NodePath.join(Os.homedir(), "projects/x"), [rules]).action, "allow", "home expansion");

		final reversed = PermissionRules.fromConfig(cast {bash: "allow", "*": "deny"});
		eq(PermissionRules.evaluate("bash", "ls", [reversed]).action, "allow", "specific beats wildcard");
	}

	static function taskPermissionRules():Void {
		eq(PermissionRules.evaluate("task", "code-reviewer", []).action, "ask", "task default ask");
		eq(PermissionRules.evaluate("task", "code-reviewer", [taskRules(cast {"code-reviewer": "deny"})]).action, "deny", "task explicit deny");
		eq(PermissionRules.evaluate("task", "code-reviewer", [taskRules(cast {"code-reviewer": "allow"})]).action, "allow", "task explicit allow");
		eq(PermissionRules.evaluate("task", "code-reviewer", [taskRules(cast {"code-reviewer": "ask"})]).action, "ask", "task explicit ask");

		final wildcardDeny = taskRules(cast {"orchestrator-*": "deny"});
		eq(PermissionRules.evaluate("task", "orchestrator-fast", [wildcardDeny]).action, "deny", "task wildcard deny fast");
		eq(PermissionRules.evaluate("task", "orchestrator-slow", [wildcardDeny]).action, "deny", "task wildcard deny slow");
		eq(PermissionRules.evaluate("task", "general", [wildcardDeny]).action, "ask", "task wildcard deny misses");

		final wildcardAllow = taskRules(cast {"orchestrator-*": "allow"});
		eq(PermissionRules.evaluate("task", "orchestrator-fast", [wildcardAllow]).action, "allow", "task wildcard allow fast");
		eq(PermissionRules.evaluate("task", "orchestrator-slow", [wildcardAllow]).action, "allow", "task wildcard allow slow");
		eq(PermissionRules.evaluate("task", "any-agent", [taskRules(cast {"*": "allow"})]).action, "allow", "task global allow");
		eq(PermissionRules.evaluate("task", "any-agent", [taskRules(cast {"*": "deny"})]).action, "deny", "task global deny");
		eq(PermissionRules.evaluate("task", "any-agent", [taskRules(cast {"*": "ask"})]).action, "ask", "task global ask");

		final laterSpecific = taskRules(cast {"orchestrator-*": "deny", "orchestrator-fast": "allow"});
		eq(PermissionRules.evaluate("task", "orchestrator-fast", [laterSpecific]).action, "allow", "task later specific wins");
		eq(PermissionRules.evaluate("task", "orchestrator-slow", [laterSpecific]).action, "deny", "task earlier wildcard remains");

		eq(PermissionRules.disabled(["task"], taskRules(cast {"*": "deny"})).join(","), "task", "task disabled global deny");
		eq(PermissionRules.disabled(["task"], taskRules(cast {"orchestrator-*": "deny", general: "deny"})).length, 0, "task not disabled by specific denies");
		eq(PermissionRules.disabled(["task"], taskRules(cast {"*": "deny", "orchestrator-coder": "allow"})).length, 0,
			"task not disabled when later specific rule wins");

		final configAllowSpecificDeny = PermissionRules.fromConfig(cast {
			task: {"*": "allow", "code-reviewer": "deny"}
		});
		eq(PermissionRules.evaluate("task", "general", [configAllowSpecificDeny]).action, "allow", "task config global allow");
		eq(PermissionRules.evaluate("task", "orchestrator-fast", [configAllowSpecificDeny]).action, "allow", "task config wildcard allow");
		eq(PermissionRules.evaluate("task", "code-reviewer", [configAllowSpecificDeny]).action, "deny", "task config specific deny");

		final mixed = PermissionRules.fromConfig(cast {
			bash: "allow",
			edit: "ask",
			task: {"*": "deny", general: "allow"}
		});
		eq(PermissionRules.evaluate("task", "general", [mixed]).action, "allow", "task mixed general allow");
		eq(PermissionRules.evaluate("task", "code-reviewer", [mixed]).action, "deny", "task mixed default deny");
		eq(PermissionRules.evaluate("bash", "*", [mixed]).action, "allow", "task mixed bash allow");
		eq(PermissionRules.evaluate("edit", "*", [mixed]).action, "ask", "task mixed edit ask");
		eq(PermissionRules.disabled(["bash", "edit", "task"], mixed).length, 0, "task mixed disabled respects last match");

		final denyLast = PermissionRules.fromConfig(cast {
			task: {general: "allow", "code-reviewer": "allow", "*": "deny"}
		});
		eq(PermissionRules.evaluate("task", "general", [denyLast]).action, "deny", "task config deny last general");
		eq(PermissionRules.evaluate("task", "code-reviewer", [denyLast]).action, "deny", "task config deny last reviewer");
		eq(PermissionRules.evaluate("task", "unknown", [denyLast]).action, "deny", "task config deny last unknown");
		eq(PermissionRules.disabled(["task"], denyLast).join(","), "task", "task disabled when deny wildcard last");
	}

	static function taskRules(rules:Dynamic<String>):Array<PermissionRule> {
		final result:Array<PermissionRule> = [];
		for (pattern in Reflect.fields(rules)) {
			result.push({
				permission: "task",
				pattern: pattern,
				action: Std.string(Reflect.field(rules, pattern)),
			});
		}
		return result;
	}

	static function disabledTools():Void {
		final rules:Array<PermissionRule> = [
			{permission: "edit", pattern: "*", action: "deny"},
			{permission: "bash", pattern: "rm *", action: "deny"},
			{permission: "task", pattern: "*", action: "deny"},
		];
		final disabled = PermissionRules.disabled(["read", "write", "edit", "apply_patch", "bash", "task"], rules);
		eq(disabled.join(","), "write,edit,apply_patch,task", "disabled tools");
	}

	static function runtimeAskReply():Void {
		final seen:Array<String> = [];
		final runtime = new PermissionRuntime({
			sessionID: "ses_perm",
			messageID: "msg_perm",
			callID: "call_perm",
			ruleset: [{permission: "read", pattern: "*", action: "ask"}],
			prompt: request -> {
				seen.push(request.id + ":" + request.permission + ":" + request.patterns.join(","));
				return {reply: "always"};
			}
		});
		final first = runtime.ask({
			permission: "read",
			patterns: ["src/a.ts"],
			always: ["src/*"],
			metadata: ToolPermissionMetadata.checked({})
		});
		eq(first.allowed, true, "first ask allowed");
		eq(seen.length, 1, "prompt called");
		final second = runtime.ask({
			permission: "read",
			patterns: ["src/b.ts"],
			always: ["src/*"],
			metadata: ToolPermissionMetadata.checked({})
		});
		eq(second.allowed, true, "approved always allowed");
		eq(seen.length, 1, "prompt not called after always");

		final reject = new PermissionRuntime({
			sessionID: "ses_perm",
			ruleset: [{permission: "bash", pattern: "*", action: "ask"}],
			prompt: _ -> {
				return {reply: "reject", message: "no thanks"};
			}
		});
		final denied = reject.ask({
			permission: "bash",
			patterns: ["pwd"],
			always: ["pwd *"],
			metadata: ToolPermissionMetadata.checked({})
		});
		eq(denied.allowed, false, "reject denied");
		eq(denied.reason, "no thanks", "reject reason");
	}

	static function toolIntegration():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-permission-"));
		try {
			Fs.mkdirSync(NodePath.join(root, "src"), {recursive: true});
			Fs.writeFileSync(NodePath.join(root, "src/a.ts"), "ok\n");
			final registry = new ToolRegistry();
			final allow = new PermissionRuntime({
				sessionID: "ses_perm",
				ruleset: [
					{permission: "read", pattern: "src/*", action: "allow"},
					{permission: "bash", pattern: "printf *", action: "allow"},
				]
			});
			final ctx = context(root, allow);
			final read = registry.execute(ToolIDs.known("read"), {filePath: "src/a.ts"}, ctx);
			eq(read.output.indexOf("ok") != -1, true, "permission read integration");
			final bash = registry.execute(ToolIDs.known("bash"), {command: "printf ok", description: "Print ok"}, ctx);
			eq(bash.output, "ok", "permission bash integration");

			final deny = new PermissionRuntime({
				sessionID: "ses_perm",
				ruleset: [{permission: "bash", pattern: "*", action: "deny"}]
			});
			expectToolFailure(() -> registry.execute(ToolIDs.known("bash"), {command: "printf no", description: "Denied"}, context(root, deny)),
				function(failure) {
					return switch failure {
						case PermissionDenied(id, message): id == "bash" && message.indexOf("prevents this tool call") != -1;
						case _: false;
					}
				}, "permission deny integration");
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function context(root:String, runtime:PermissionRuntime):ToolContext {
		return {
			directory: root,
			worktree: root,
			sessionID: "ses_perm",
			messageID: "msg_perm",
			callID: "call_perm",
			agent: "build",
			ask: runtime.toToolAsk(),
		};
	}

	static function expectToolFailure(run:() -> Void, matches:ToolFailure->Bool, label:String):Void {
		try {
			run();
		} catch (error:ToolException) {
			if (matches(error.failure))
				return;
			throw '${label}: unexpected failure ${error.message}';
		}
		throw '${label}: expected failure';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
