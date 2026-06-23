package opencodehx.smoke;

import opencodehx.externs.node.Os;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.permission.PermissionRules;
import opencodehx.permission.PermissionRuntime;
import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolError.ToolFailure;
import opencodehx.tool.ToolRegistry;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolIDs;

class PermissionSmoke {
	public static function run():Void {
		fromConfigAndEvaluate();
		disabledTools();
		runtimeAskReply();
		toolIntegration();
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
			metadata: {}
		});
		eq(first.allowed, true, "first ask allowed");
		eq(seen.length, 1, "prompt called");
		final second = runtime.ask({
			permission: "read",
			patterns: ["src/b.ts"],
			always: ["src/*"],
			metadata: {}
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
			metadata: {}
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
