package opencodehx.smoke;

import genes.ts.Unknown;
import haxe.DynamicAccess;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.lsp.LspClient;
import opencodehx.lsp.LspDiagnostic;
import opencodehx.lsp.LspRuntime;
import opencodehx.lsp.LspTypes.LspDiagnosticInfo;
import opencodehx.lsp.LspTypes.LspEndpointResult;
import opencodehx.lsp.LspTypes.LspInitializeRequest;
import opencodehx.lsp.LspTypes.LspRuntimeContext;
import opencodehx.lsp.LspTypes.LspServerHandle;
import opencodehx.tool.LspTool;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolError.ToolFailure;
import opencodehx.tool.ToolRegistry;
import opencodehx.tool.ToolTypes.ToolContext;

class LspSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-lsp-"));
		try {
			write(root, "src/test.ts", "export const value = 1;\n");
			diagnostics();
			lifecycle(root);
			clientInterop(root);
			initializeFailures(root);
			toolIntegration(root);
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			// Smoke cleanup must run for arbitrary Haxe/JS failures before the
			// original cause is rethrown to the shared smoke runner.
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function diagnostics():Void {
		final diagnostic:LspDiagnosticInfo = {
			range: {start: {line: 9, character: 4}, end: {line: 9, character: 10}},
			message: "Type mismatch",
			severity: 1,
		};
		eq(LspDiagnostic.pretty(diagnostic), "ERROR [10:5] Type mismatch", "lsp diagnostic error");
		final warning:LspDiagnosticInfo = {
			range: {start: {line: 0, character: 0}, end: {line: 0, character: 5}},
			message: "Unused variable",
			severity: 2,
		};
		eq(LspDiagnostic.pretty(warning), "WARN [1:1] Unused variable", "lsp diagnostic warning");
		final missingSeverity:LspDiagnosticInfo = {
			range: {start: {line: 0, character: 0}, end: {line: 0, character: 1}},
			message: "Missing severity",
		};
		eq(LspDiagnostic.pretty(missingSeverity), "ERROR [1:1] Missing severity", "lsp diagnostic default severity");
		eq(LspDiagnostic.report("src/test.ts", [diagnostic]).indexOf('<diagnostics file="src/test.ts">') == 0, true, "lsp diagnostic report wrapper");
	}

	static function lifecycle(root:String):Void {
		final file = NodePath.join(root, "src/test.ts");
		final disabled = new LspRuntime({directory: root, enabled: false});
		disabled.init();
		disabled.init();
		eq(disabled.status().length, 0, "lsp status empty initially");
		eq(hasKeys(disabled.diagnostics()), false, "lsp diagnostics empty initially");
		eq(disabled.hasClients(file), false, "lsp disabled has no clients");
		eq(disabled.hasClients(NodePath.join(root, "../outside.ts")), false, "lsp outside file has no clients");
		eq(disabled.workspaceSymbol("test").length, 0, "lsp workspace symbol empty with no clients");

		final fixture = new LspFixture();
		final runtime = new LspRuntime({
			directory: root,
			enabled: true,
			disabled: ["eslint"],
			servers: [LspRuntime.typescriptServer(fixture.spawn)],
		});
		eq(runtime.hasClients(file), true, "lsp typescript available when enabled");
		eq(runtime.status().length, 0, "lsp hasClients does not spawn");
		eq(runtime.hover({file: file, line: 0, character: 0}).length, 1, "lsp hover returns response");
		eq(fixture.spawnCount, 1, "lsp hover spawns once");
		eq(runtime.status()[0].status, "connected", "lsp connected status");
		runtime.touchFile(file, true);
		eq(fixture.spawnCount, 1, "lsp touch reuses client");
		runtime.shutdown();
		eq(fixture.endpoints[0].shutdowns, 1, "lsp shutdown closes endpoint");

		write(root, "deno.json", "{}\n");
		final denoRuntime = new LspRuntime({
			directory: root,
			enabled: true,
			servers: [LspRuntime.typescriptServer(fixture.spawn)],
		});
		eq(denoRuntime.hasClients(file), false, "lsp typescript excluded by deno marker");
		Fs.rmSync(NodePath.join(root, "deno.json"), {force: true});
	}

	static function clientInterop(root:String):Void {
		final endpoint = new FakeLspEndpoint();
		final client = new LspClient("fake", root, root, {endpoint: endpoint, processId: 123});
		eq(endpoint.initializeCalls, 1, "lsp client initializes endpoint");
		endpoint.triggerClientRequest("workspace/workspaceFolders");
		endpoint.triggerClientRequest("client/registerCapability");
		endpoint.triggerClientRequest("client/unregisterCapability");
		eq(endpoint.clientRequestMethods.join(","), "workspace/workspaceFolders,client/registerCapability,client/unregisterCapability",
			"lsp client handles server requests");
		client.shutdown();
		eq(endpoint.shutdowns, 1, "lsp client shutdown");
	}

	static function initializeFailures(root:String):Void {
		final failed = new LspFixture();
		failed.nextMode = Failure("boom");
		final failedRuntime = new LspRuntime({
			directory: root,
			enabled: true,
			servers: [LspRuntime.typescriptServer(failed.spawn)],
		});
		eq(failedRuntime.hover({file: NodePath.join(root, "src/test.ts"), line: 0, character: 0}).length, 0, "lsp init failure returns no result");
		eq(failedRuntime.hasClients(NodePath.join(root, "src/test.ts")), false, "lsp init failure marks server broken");
		eq(failed.endpoints[0].shutdowns, 1, "lsp init failure shuts down endpoint");

		final timedOut = new LspFixture();
		timedOut.nextMode = Timeout;
		final timeoutRuntime = new LspRuntime({
			directory: root,
			enabled: true,
			servers: [LspRuntime.typescriptServer(timedOut.spawn)],
		});
		eq(timeoutRuntime.definition({file: NodePath.join(root, "src/test.ts"), line: 0, character: 0}).length, 0, "lsp init timeout returns no result");
		eq(timeoutRuntime.hasClients(NodePath.join(root, "src/test.ts")), false, "lsp init timeout marks server broken");
	}

	static function toolIntegration(root:String):Void {
		final fixture = new LspFixture();
		final runtime = new LspRuntime({
			directory: root,
			enabled: true,
			servers: [LspRuntime.typescriptServer(fixture.spawn)],
		});
		final registry = new ToolRegistry([LspTool.define(runtime)]);
		final permissions:Array<String> = [];
		final ctx:ToolContext = {
			directory: root,
			worktree: root,
			ask: request -> {
				permissions.push(request.permission);
				return {allowed: true};
			},
		};
		final result = registry.execute("lsp", {
			operation: "hover",
			filePath: "src/test.ts",
			line: 1,
			character: 1,
		}, ctx);
		eq(result.title, "hover src/test.ts:1:1", "lsp tool title");
		eq(permissions.join(","), "lsp", "lsp tool permission");
		eq(Reflect.field(result.metadata, "result").length, 1, "lsp tool metadata result");
		expectToolFailure(() -> registry.execute("lsp", {
			operation: "hover",
			filePath: "src/missing.ts",
			line: 1,
			character: 1,
		}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "lsp" && message.indexOf("File not found") != -1;
				case _: false;
			}
		}, "lsp tool missing file");
	}

	static function write(root:String, rel:String, content:String):Void {
		final file = NodePath.join(root, rel);
		Fs.mkdirSync(NodePath.dirname(file), {recursive: true});
		Fs.writeFileSync(file, content, {encoding: "utf8"});
	}

	static function expectToolFailure(fn:Void->Void, pred:ToolFailure->Bool, label:String):Void {
		try {
			fn();
			throw '${label}: expected failure';
		} catch (error:ToolException) {
			if (!pred(error.failure))
				throw '${label}: unexpected failure ${error.message}';
		}
	}

	static function hasKeys<T>(access:DynamicAccess<T>):Bool {
		for (_ in access.keys())
			return true;
		return false;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}

enum LspEndpointMode {
	Ready;
	Failure(message:String);
	Timeout;
}

class LspFixture {
	public var spawnCount(default, null):Int = 0;
	public var nextMode:LspEndpointMode = Ready;
	public final endpoints:Array<FakeLspEndpoint> = [];

	public function new() {}

	public function spawn(_root:String, _ctx:LspRuntimeContext):Null<LspServerHandle> {
		spawnCount++;
		final endpoint = new FakeLspEndpoint(nextMode);
		endpoints.push(endpoint);
		return {endpoint: endpoint, processId: 123};
	}
}

class FakeLspEndpoint {
	public final notifications:Array<String> = [];
	public final requests:Array<String> = [];
	public final clientRequestMethods:Array<String> = [];
	public var initializeCalls(default, null):Int = 0;
	public var shutdowns(default, null):Int = 0;

	final mode:LspEndpointMode;
	var handler:Null<String->Unknown> = null;

	public function new(?mode:LspEndpointMode) {
		this.mode = mode == null ? Ready : mode;
	}

	public function setClientRequestHandler(handler:String->Unknown):Void {
		this.handler = handler;
	}

	public function initialize(_request:LspInitializeRequest):LspEndpointResult {
		initializeCalls++;
		return switch mode {
			case Ready:
				{ok: true, value: Unknown.fromBoundary({capabilities: {}})};
			case Failure(message):
				{ok: false, error: message};
			case Timeout:
				{ok: false, timeout: true};
		}
	}

	public function sendRequest(method:String, _params:Unknown):LspEndpointResult {
		requests.push(method);
		return {ok: true, value: Unknown.fromBoundary({method: method})};
	}

	public function sendNotification(method:String, _params:Unknown):Void {
		notifications.push(method);
	}

	public function shutdown():Void {
		shutdowns++;
	}

	public function triggerClientRequest(method:String):Void {
		if (handler == null)
			throw 'lsp fake endpoint has no client request handler';
		clientRequestMethods.push(method);
		handler(method);
	}
}
