package opencodehx.smoke;

import genes.js.Async.await;
import js.lib.Promise;
import opencodehx.externs.node.Os;
import opencodehx.externs.node.Fs;
import opencodehx.config.ConfigLoader;
import opencodehx.host.node.NodePath;
import opencodehx.permission.BashArity;
import opencodehx.permission.PermissionAsyncRuntime;
import opencodehx.permission.PermissionAsyncRuntime.PermissionCorrectedError;
import opencodehx.permission.PermissionAsyncRuntime.PermissionDeniedError;
import opencodehx.permission.PermissionAsyncRuntime.PermissionRejectedError;
import opencodehx.permission.PermissionRules;
import opencodehx.permission.PermissionRuntime;
import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.project.InstanceRuntime;
import opencodehx.project.InstanceRuntime.InstanceContext;
import opencodehx.project.InstanceRuntime.InstanceServiceID;
import opencodehx.project.ProjectRuntime;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolError.ToolFailure;
import opencodehx.tool.ToolRegistry;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolIDs;
import opencodehx.tool.ToolTypes.ToolPermissionMetadata;

class PermissionSmoke {
	public static function run():Void {
		fromConfigAndEvaluate();
		mergeAndEvaluate();
		taskPermissionRules();
		bashArityPrefix();
		disabledTools();
		runtimeAskReply();
		toolIntegration();
	}

	@:async
	public static function runAsync():Promise<Void> {
		ProjectRuntime.reset();
		InstanceRuntime.reset();
		PermissionAsyncRuntime.reset();
		await(asyncAskListReply());
		await(asyncRejectAndAlways());
		await(asyncDirectoryIsolation());
		await(asyncDisposeReload());
		await(asyncRuleShortCircuit());
		PermissionAsyncRuntime.reset();
		InstanceRuntime.reset();
		ProjectRuntime.reset();
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
		final rules = configRules('{"*":"ask","bash":{"*":"allow","rm *":"deny"},"edit":"deny","external_directory":{"~/projects/*":"allow"}}');
		eq(PermissionRules.evaluate("bash", "git status", [rules]).action, "allow", "bash allow");
		eq(PermissionRules.evaluate("bash", "rm -rf tmp", [rules]).action, "deny", "bash deny");
		eq(PermissionRules.evaluate("edit", "src/a.ts", [rules]).action, "deny", "edit deny");
		eq(PermissionRules.evaluate("read", "src/a.ts", [rules]).action, "ask", "wildcard fallback");
		eq(PermissionRules.evaluate("external_directory", NodePath.join(Os.homedir(), "projects/x"), [rules]).action, "allow", "home expansion");

		final reversed = configRules('{"bash":"allow","*":"deny"}');
		eq(PermissionRules.evaluate("bash", "ls", [reversed]).action, "allow", "specific beats wildcard");

		final expanded = configRules('{"external_directory":{"~":"allow","$$HOME":"allow","$$HOME/projects/*":"allow","/some/~/path":"deny"}}');
		eq(expanded[0].pattern, Os.homedir(), "exact tilde expands");
		eq(expanded[1].pattern, Os.homedir(), "exact HOME expands");
		eq(expanded[2].pattern, NodePath.join(Os.homedir(), "projects/*"), "HOME prefix expands");
		eq(expanded[3].pattern, "/some/~/path", "middle tilde unchanged");
	}

	static function mergeAndEvaluate():Void {
		final merged = PermissionRules.merge([
			[
				{permission: "edit", pattern: "src/*", action: "allow"},
				{permission: "edit", pattern: "src/secret/*", action: "deny"}
			],
			[{permission: "edit", pattern: "src/secret/ok.ts", action: "allow"}],
		]);
		eq(merged[0].pattern, "src/*", "merge preserves first rule");
		eq(merged[1].pattern, "src/secret/*", "merge preserves second rule");
		eq(merged[2].pattern, "src/secret/ok.ts", "merge appends later rules");
		eq(PermissionRules.evaluate("edit", "src/secret/ok.ts", [merged]).action, "allow", "merged last match wins");
		eq(PermissionRules.evaluate("edit", "src/secret/no.ts", [merged]).action, "deny", "merged middle match wins");
		eq(PermissionRules.evaluate("edit", "src/components/Button.tsx", [
			[
				{permission: "edit", pattern: "src/components/*", action: "allow"},
				{permission: "edit", pattern: "src/*", action: "deny"},
			]
		]).action, "deny", "specificity follows order");
		eq(PermissionRules.evaluate("mcp_dangerous", "anything", [
			[
				{permission: "*", pattern: "*", action: "ask"},
				{permission: "mcp_*", pattern: "*", action: "allow"},
				{permission: "mcp_dangerous", pattern: "*", action: "deny"},
			]
		]).action, "deny", "multiple wildcard permission patterns combine by order");
		eq(PermissionRules.evaluate("unknown_tool", "anything", [[{permission: "bash", pattern: "*", action: "allow"}]]).action, "ask",
			"unknown permission asks");
	}

	static function taskPermissionRules():Void {
		eq(PermissionRules.evaluate("task", "code-reviewer", []).action, "ask", "task default ask");
		eq(PermissionRules.evaluate("task", "code-reviewer", [taskRules([pattern("code-reviewer", "deny")])]).action, "deny", "task explicit deny");
		eq(PermissionRules.evaluate("task", "code-reviewer", [taskRules([pattern("code-reviewer", "allow")])]).action, "allow", "task explicit allow");
		eq(PermissionRules.evaluate("task", "code-reviewer", [taskRules([pattern("code-reviewer", "ask")])]).action, "ask", "task explicit ask");

		final wildcardDeny = taskRules([pattern("orchestrator-*", "deny")]);
		eq(PermissionRules.evaluate("task", "orchestrator-fast", [wildcardDeny]).action, "deny", "task wildcard deny fast");
		eq(PermissionRules.evaluate("task", "orchestrator-slow", [wildcardDeny]).action, "deny", "task wildcard deny slow");
		eq(PermissionRules.evaluate("task", "general", [wildcardDeny]).action, "ask", "task wildcard deny misses");

		final wildcardAllow = taskRules([pattern("orchestrator-*", "allow")]);
		eq(PermissionRules.evaluate("task", "orchestrator-fast", [wildcardAllow]).action, "allow", "task wildcard allow fast");
		eq(PermissionRules.evaluate("task", "orchestrator-slow", [wildcardAllow]).action, "allow", "task wildcard allow slow");
		eq(PermissionRules.evaluate("task", "any-agent", [taskRules([pattern("*", "allow")])]).action, "allow", "task global allow");
		eq(PermissionRules.evaluate("task", "any-agent", [taskRules([pattern("*", "deny")])]).action, "deny", "task global deny");
		eq(PermissionRules.evaluate("task", "any-agent", [taskRules([pattern("*", "ask")])]).action, "ask", "task global ask");

		final laterSpecific = taskRules([pattern("orchestrator-*", "deny"), pattern("orchestrator-fast", "allow")]);
		eq(PermissionRules.evaluate("task", "orchestrator-fast", [laterSpecific]).action, "allow", "task later specific wins");
		eq(PermissionRules.evaluate("task", "orchestrator-slow", [laterSpecific]).action, "deny", "task earlier wildcard remains");

		eq(PermissionRules.disabled(["task"], taskRules([pattern("*", "deny")])).join(","), "task", "task disabled global deny");
		eq(PermissionRules.disabled(["task"], taskRules([pattern("orchestrator-*", "deny"), pattern("general", "deny")])).length, 0,
			"task not disabled by specific denies");
		eq(PermissionRules.disabled(["task"], taskRules([pattern("*", "deny"), pattern("orchestrator-coder", "allow")])).length, 0,
			"task not disabled when later specific rule wins");

		final configAllowSpecificDeny = configRules('{"task":{"*":"allow","code-reviewer":"deny"}}');
		eq(PermissionRules.evaluate("task", "general", [configAllowSpecificDeny]).action, "allow", "task config global allow");
		eq(PermissionRules.evaluate("task", "orchestrator-fast", [configAllowSpecificDeny]).action, "allow", "task config wildcard allow");
		eq(PermissionRules.evaluate("task", "code-reviewer", [configAllowSpecificDeny]).action, "deny", "task config specific deny");

		final mixed = configRules('{"bash":"allow","edit":"ask","task":{"*":"deny","general":"allow"}}');
		eq(PermissionRules.evaluate("task", "general", [mixed]).action, "allow", "task mixed general allow");
		eq(PermissionRules.evaluate("task", "code-reviewer", [mixed]).action, "deny", "task mixed default deny");
		eq(PermissionRules.evaluate("bash", "*", [mixed]).action, "allow", "task mixed bash allow");
		eq(PermissionRules.evaluate("edit", "*", [mixed]).action, "ask", "task mixed edit ask");
		eq(PermissionRules.disabled(["bash", "edit", "task"], mixed).length, 0, "task mixed disabled respects last match");

		final denyLast = configRules('{"task":{"general":"allow","code-reviewer":"allow","*":"deny"}}');
		eq(PermissionRules.evaluate("task", "general", [denyLast]).action, "deny", "task config deny last general");
		eq(PermissionRules.evaluate("task", "code-reviewer", [denyLast]).action, "deny", "task config deny last reviewer");
		eq(PermissionRules.evaluate("task", "unknown", [denyLast]).action, "deny", "task config deny last unknown");
		eq(PermissionRules.disabled(["task"], denyLast).join(","), "task", "task disabled when deny wildcard last");
	}

	static function taskRules(rules:Array<{final name:String; final action:String;}>):Array<PermissionRule> {
		final result:Array<PermissionRule> = [];
		for (rule in rules) {
			result.push({
				permission: "task",
				pattern: rule.name,
				action: rule.action,
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

		eq(PermissionRules.disabled(["bash", "edit", "read"], [{permission: "*", pattern: "*", action: "allow"}]).length, 0, "allow wildcard disables none");
		eq(PermissionRules.disabled(["bash", "edit", "read"], [{permission: "*", pattern: "*", action: "deny"}]).join(","), "bash,edit,read",
			"deny wildcard disables all");
		eq(PermissionRules.disabled(["bash"], [
			{permission: "bash", pattern: "*", action: "deny"},
			{permission: "bash", pattern: "echo *", action: "allow"},
		]).length, 0, "specific allow after wildcard deny keeps tool enabled");
		eq(PermissionRules.disabled(["bash"], [
			{permission: "bash", pattern: "rm *", action: "deny"},
			{permission: "bash", pattern: "*", action: "allow"},
		]).length, 0, "wildcard allow after specific deny keeps tool enabled");
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

	@:async
	static function asyncAskListReply():Promise<Void> {
		final context = bootTempContext("permission-async-basic");
		final service = PermissionAsyncRuntime.forContext(context);
		final promise = service.ask(askInput("per_async_1", "ses_async", "bash", ["ls"], [], [], {
			messageID: "msg_perm_async",
			callID: "call_perm_async",
		}));

		final pending = await(service.list());
		eq(pending.length, 1, "async permission pending count");
		eq(pending[0].sessionID, "ses_async", "async permission pending session");
		eq(pending[0].permission, "bash", "async permission pending permission");
		eq(pending[0].patterns.join(","), "ls", "async permission pending patterns");
		eq(requireAsyncTool(pending[0]).callID, "call_perm_async", "async permission pending tool");

		await(service.reply({requestID: "per_async_1", reply: {reply: "once"}}));
		eq(await(promise), true, "async permission once resolves");
		eq((await(service.list())).length, 0, "async permission once removes pending");
		await(service.reply({requestID: "per_missing", reply: {reply: "once"}}));
		InstanceRuntime.dispose(context.directory);
	}

	@:async
	static function asyncRejectAndAlways():Promise<Void> {
		final context = bootTempContext("permission-async-reply");
		final service = PermissionAsyncRuntime.forContext(context);

		final first = service.ask(askInput("per_reject_a", "ses_reject", "bash", ["ls"], [], []));
		final second = service.ask(askInput("per_reject_b", "ses_reject", "edit", ["src/a.ts"], [], []));
		final other = service.ask(askInput("per_reject_other", "ses_other", "bash", ["pwd"], [], []));
		eq((await(service.list())).length, 3, "async permission reject pending count");
		await(service.reply({requestID: "per_reject_a", reply: {reply: "reject"}}));
		eq(await(permissionOutcome(first)), "rejected", "async permission reject first");
		eq(await(permissionOutcome(second)), "rejected", "async permission reject same session");
		eq((await(service.list())).length, 1, "async permission reject keeps other session");
		await(service.reply({requestID: "per_reject_other", reply: {reply: "reject", message: "Use a safer command"}}));
		eq(await(permissionOutcome(other)), "corrected", "async permission reject message");

		final alwaysA = service.ask(askInput("per_always_a", "ses_always", "bash", ["ls"], ["ls"], []));
		final alwaysB = service.ask(askInput("per_always_b", "ses_always", "bash", ["ls"], [], []));
		final alwaysOther = service.ask(askInput("per_always_other", "ses_always_other", "bash", ["ls"], [], []));
		eq((await(service.list())).length, 3, "async permission always pending count");
		await(service.reply({requestID: "per_always_a", reply: {reply: "always"}}));
		eq(await(alwaysA), true, "async permission always selected resolves");
		eq(await(alwaysB), true, "async permission always matching same session resolves");
		final remaining = await(service.list());
		eq(remaining.length, 1, "async permission always keeps other session");
		eq(remaining[0].id, "per_always_other", "async permission always remaining id");
		eq(await(service.ask(askInput(null, "ses_after_always", "bash", ["ls"], [], []))), true, "async permission always persists approval");
		await(service.reply({requestID: "per_always_other", reply: {reply: "reject"}}));
		eq(await(permissionOutcome(alwaysOther)), "rejected", "async permission cleanup other session");
		InstanceRuntime.dispose(context.directory);
	}

	@:async
	static function asyncDirectoryIsolation():Promise<Void> {
		final one = bootTempContext("permission-async-one");
		final two = bootTempContext("permission-async-two");
		final serviceOne = PermissionAsyncRuntime.forContext(one);
		final serviceTwo = PermissionAsyncRuntime.forContext(two);
		final a = serviceOne.ask(askInput("per_dir_a", "ses_dir_a", "bash", ["ls"], [], []));
		final b = serviceTwo.ask(askInput("per_dir_b", "ses_dir_b", "bash", ["pwd"], [], []));

		final onePending = await(serviceOne.list());
		final twoPending = await(serviceTwo.list());
		eq(onePending.length, 1, "async permission directory one count");
		eq(twoPending.length, 1, "async permission directory two count");
		eq(onePending[0].id, "per_dir_a", "async permission directory one id");
		eq(twoPending[0].id, "per_dir_b", "async permission directory two id");

		await(serviceOne.reply({requestID: "per_dir_a", reply: {reply: "reject"}}));
		await(serviceTwo.reply({requestID: "per_dir_b", reply: {reply: "reject"}}));
		eq(await(permissionOutcome(a)), "rejected", "async permission directory one reject");
		eq(await(permissionOutcome(b)), "rejected", "async permission directory two reject");
		InstanceRuntime.dispose(one.directory);
		InstanceRuntime.dispose(two.directory);
	}

	@:async
	static function asyncDisposeReload():Promise<Void> {
		final disposed = bootTempContext("permission-async-dispose");
		final disposeService = PermissionAsyncRuntime.forContext(disposed);
		final disposePromise = disposeService.ask(askInput("per_dispose", "ses_dispose", "bash", ["ls"], [], []));
		eq((await(disposeService.list())).length, 1, "async permission dispose pending");
		InstanceRuntime.dispose(disposed.directory);
		eq(await(permissionOutcome(disposePromise)), "rejected", "async permission dispose rejects");

		final reloaded = bootTempContext("permission-async-reload");
		final reloadService = PermissionAsyncRuntime.forContext(reloaded);
		final reloadPromise = reloadService.ask(askInput("per_reload", "ses_reload", "bash", ["ls"], [], []));
		eq((await(reloadService.list())).length, 1, "async permission reload pending");
		final project = ProjectRuntime.fromDirectory(reloaded.directory).project;
		InstanceRuntime.reload({
			directory: reloaded.directory,
			worktree: reloaded.worktree,
			project: project,
			services: [ctx->{id: InstanceServiceID.Command}],
		});
		eq(await(permissionOutcome(reloadPromise)), "rejected", "async permission reload rejects");
		InstanceRuntime.dispose(reloaded.directory);
	}

	@:async
	static function asyncRuleShortCircuit():Promise<Void> {
		final context = bootTempContext("permission-async-rules");
		final service = PermissionAsyncRuntime.forContext(context);
		final denied = service.ask(askInput("per_deny", "ses_deny", "bash", ["echo hello", "rm -rf /"], [], [
			{permission: "bash", pattern: "echo *", action: "ask"},
			{permission: "bash", pattern: "rm *", action: "deny"},
		]));
		eq(await(permissionOutcome(denied)), "denied", "async permission deny beats earlier ask");
		eq((await(service.list())).length, 0, "async permission deny leaves no pending");
		eq(await(service.ask(askInput("per_allow", "ses_allow", "bash", ["echo hello", "ls -la"], [], [{permission: "bash", pattern: "*", action: "allow"}]))),
			true, "async permission all allow resolves");
		InstanceRuntime.dispose(context.directory);
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

	static function pattern(name:String, action:String):{final name:String; final action:String;} {
		return {name: name, action: action};
	}

	static function configRules(permissionJson:String):Array<PermissionRule> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-permission-config-"));
		try {
			Fs.writeFileSync(NodePath.join(root, "opencode.json"), '{"permission":${permissionJson}}');
			final config = ConfigLoader.loadProject(root, {defaultUsername: "fixture-user"});
			final rules = PermissionRules.fromConfig(config.permission);
			Fs.rmSync(root, {recursive: true, force: true});
			return rules;
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function bootTempContext(label:String):InstanceContext {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), 'opencodehx-${label}-'));
		final project = ProjectRuntime.fromDirectory(root).project;
		final context = InstanceRuntime.boot({
			directory: root,
			worktree: root,
			project: project,
			services: [ctx->{id: InstanceServiceID.Command}],
		});
		if (context == null)
			throw '${label}: expected instance context';
		return context;
	}

	static function askInput(id:Null<String>, sessionID:String, permission:String, patterns:Array<String>, always:Array<String>,
			ruleset:Array<PermissionRule>,
			?tool:opencodehx.permission.PermissionAsyncRuntime.PermissionToolRef):opencodehx.permission.PermissionAsyncRuntime.PermissionAskInput {
		return {
			id: id,
			sessionID: sessionID,
			permission: permission,
			patterns: patterns,
			metadata: ToolPermissionMetadata.checked({}),
			always: always,
			ruleset: ruleset,
			tool: tool,
		};
	}

	static function requireAsyncTool(request:opencodehx.permission.PermissionTypes.PermissionAskRecord):opencodehx.permission.PermissionAsyncRuntime.PermissionToolRef {
		final tool = request.tool;
		if (tool == null)
			throw "async permission expected tool metadata";
		return {messageID: tool.messageID, callID: tool.callID};
	}

	static function permissionOutcome(promise:Promise<Bool>):Promise<String> {
		return promise.then(_ -> "resolved").catchError(error -> {
			// JavaScript Promise rejection reasons are arbitrary host values.
			if (Std.isOfType(error, PermissionDeniedError))
				return "denied";
			if (Std.isOfType(error, PermissionCorrectedError))
				return "corrected";
			return Std.isOfType(error, PermissionRejectedError) ? "rejected" : "other";
		});
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
