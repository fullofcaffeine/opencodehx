package opencodehx.smoke;

import genes.ts.Unknown;
import haxe.DynamicAccess;
import opencodehx.acp.AcpAgent;
import opencodehx.acp.AcpAgent.AcpEventType;
import opencodehx.acp.AcpAgent.AcpPermissionDecision;
import opencodehx.acp.AcpAgent.AcpPermissionReply;
import opencodehx.acp.AcpAgent.AcpPermissionRequest;
import opencodehx.acp.AcpAgent.AcpPermissionOutcome;
import opencodehx.acp.AcpAgent.AcpSessionUpdate;
import opencodehx.acp.AcpAgent.AcpSessionUpdateKind;
import opencodehx.mcp.McpNeedsAuth;
import opencodehx.mcp.McpRuntime;
import opencodehx.mcp.McpRuntime.McpClient;
import opencodehx.mcp.McpRuntime.McpClientFactory;
import opencodehx.mcp.McpRuntime.McpPromptInfo;
import opencodehx.mcp.McpRuntime.McpResourceInfo;
import opencodehx.mcp.McpRuntime.McpToolInfo;

class McpAcpSmoke {
	public static function run():Void {
		mcpTransportOptions();
		mcpLifecycle();
		acpAgentInterface();
		acpEventRouting();
	}

	static function mcpTransportOptions():Void {
		final headers = new DynamicAccess<String>();
		headers.set("Authorization", "Bearer token");
		final withHeaders = McpRuntime.transportOptions({type: "remote", url: "https://mcp.example", headers: headers});
		eq(Reflect.hasField(withHeaders, "requestInit"), true, "mcp transport headers present");
		eq(withHeaders.requestInit.headers.get("Authorization"), "Bearer token", "mcp transport header value");
		eq(withHeaders.authProvider, true, "mcp oauth default enabled");

		final oauthDisabled = McpRuntime.transportOptions({
			type: "remote",
			url: "https://mcp.example",
			headers: headers,
			oauth: false
		});
		eq(Reflect.hasField(oauthDisabled, "authProvider"), false, "mcp oauth false omits auth provider");

		final noHeaders = McpRuntime.transportOptions({type: "remote", url: "https://mcp.example"});
		eq(Reflect.hasField(noHeaders, "requestInit"), false, "mcp transport omits empty request init");
	}

	static function mcpLifecycle():Void {
		final fixture = new SmokeMcpFixture();
		final runtime = new McpRuntime(fixture.factory);
		final alpha = fixture.client("my.special-server", [tool("do.thing")], [prompt("ask")], [resource("doc", "file:///doc.md")]);
		runtime.add("my.special-server", {type: "local", command: ["node", "server.js"]});
		eq(runtime.status().get("my.special-server").status, "connected", "mcp connected status");
		eq(alpha.listToolsCalls, 1, "mcp tool cache populated once");
		eq(runtime.tools().exists("my_special-server_do_thing"), true, "mcp tool name sanitized");
		runtime.tools();
		eq(alpha.listToolsCalls, 1, "mcp tools read from cache");

		alpha.toolDefs = [tool("next")];
		alpha.triggerToolsChanged();
		eq(alpha.listToolsCalls, 2, "mcp tool change refreshes cache");
		eq(runtime.tools().exists("my_special-server_do_thing"), false, "mcp stale cached tool removed");
		eq(runtime.tools().exists("my_special-server_next"), true, "mcp refreshed cached tool visible");
		eq(runtime.prompts().exists("my_special-server_ask"), true, "mcp prompts visible while connected");
		eq(runtime.resources().exists("my_special-server_doc"), true, "mcp resources visible while connected");

		runtime.disconnect("my.special-server");
		eq(runtime.status().get("my.special-server").status, "disabled", "mcp disconnect status");
		eq(runtime.tools().exists("my_special-server_next"), false, "mcp disconnect removes tools");
		eq(runtime.prompts().exists("my_special-server_ask"), false, "mcp prompts hidden after disconnect");
		runtime.connect("my.special-server");
		eq(runtime.status().get("my.special-server").status, "connected", "mcp reconnect status");

		final oldReplace = fixture.client("replace", [tool("old")], [], []);
		runtime.add("replace", {type: "local"});
		final nextReplace = new FakeMcpClient([tool("new")], [], []);
		fixture.clients.set("replace", nextReplace);
		runtime.add("replace", {type: "local"});
		eq(oldReplace.closed, true, "mcp replacing server closes old client");
		eq(runtime.tools().exists("replace_new"), true, "mcp replacement tools visible");

		final beforeDisabled = fixture.createCount;
		runtime.add("disabled", {type: "local", enabled: false});
		eq(fixture.createCount, beforeDisabled, "mcp disabled server does not connect");
		eq(runtime.status().get("disabled").status, "disabled", "mcp disabled status");

		fixture.failed.set("broken", true);
		runtime.add("broken", {type: "local"});
		eq(runtime.status().get("broken").status, "failed", "mcp failed status");

		fixture.needsAuth.set("login", true);
		runtime.add("login", {type: "remote", url: "https://mcp.example"});
		eq(runtime.status().get("login").status, "needs_auth", "mcp needs auth status");

		runtime.connect("missing");
		runtime.disconnect("missing");
	}

	static function acpAgentInterface():Void {
		final connection = new SmokeAcpConnection();
		final agent = new AcpAgent(connection);
		final init = agent.initialize({client: "smoke"});
		eq(init.agent, "opencodehx", "acp initialize agent");
		final created = agent.newSession({cwd: "/tmp/acp-one", mcpServers: ["main"]});
		eq(created.sessionID, "ses_acp_1", "acp new session id");
		eq(agent.prompt({sessionID: created.sessionID, prompt: "hello"}).queued, true, "acp prompt callable");
		eq(agent.cancel({sessionID: created.sessionID}).cancelled, true, "acp cancel callable");
		eq(agent.setSessionMode({sessionID: created.sessionID, mode: "build"}).sessionID, created.sessionID, "acp set mode callable");
		eq(agent.authenticate({provider: "github"}).authenticated, true, "acp authenticate callable");
		eq(agent.unstable_setSessionModel({
			sessionID: created.sessionID,
			providerID: "anthropic",
			modelID: "claude-smoke",
		}).sessionID, created.sessionID, "acp set model callable");
		final forked = agent.unstable_forkSession({sessionID: created.sessionID, cwd: "/tmp/acp-two"});
		eq(forked.sessionID, "ses_acp_2", "acp fork session id");
		eq(agent.unstable_resumeSession({sessionID: "loaded", cwd: "/tmp/acp-loaded"}).sessionID, "loaded", "acp resume callable");
		eq(agent.listSessions().sessions.length, 3, "acp list sessions");
	}

	static function acpEventRouting():Void {
		final connection = new SmokeAcpConnection();
		final agent = new AcpAgent(connection);
		final one = agent.newSession({cwd: "/tmp/acp-one"});
		final two = agent.newSession({cwd: "/tmp/acp-two"});
		agent.handleEvent({type: AcpEventType.MessagePartDelta, sessionID: one.sessionID, delta: "one-a"});
		agent.handleEvent({type: AcpEventType.MessagePartDelta, sessionID: two.sessionID, delta: "two-a"});
		agent.handleEvent({type: AcpEventType.MessagePartDelta, sessionID: "missing", delta: "skip"});
		eq(connection.agentChunks(one.sessionID).join(","), "one-a", "acp delta scoped to first session");
		eq(connection.agentChunks(two.sessionID).join(","), "two-a", "acp delta scoped to second session");

		final beforeUserTextUpdate = connection.updates.length;
		agent.handleEvent({
			type: AcpEventType.MessagePartUpdated,
			sessionID: one.sessionID,
			messageRole: "user",
			partType: "text",
			delta: "live user prompt",
		});
		eq(connection.updates.length, beforeUserTextUpdate, "acp live user text update skipped");

		agent.loadSession({sessionID: "loaded", cwd: "/tmp/acp-loaded"});
		agent.loadSession({sessionID: "loaded", cwd: "/tmp/acp-loaded"});
		eq(agent.eventSubscribeCount, 3, "acp load session subscription deduped");

		agent.handleEvent({type: AcpEventType.PermissionAsked, sessionID: one.sessionID, permissionID: "perm-1"});
		eq(connection.permissionReplies.length, 1, "acp permission reply emitted");
		eq(connection.permissionReplies[0].outcome, AcpPermissionOutcome.Allow, "acp permission allowed");
		eq(connection.permissionRequests[0].permissionID, "perm-1", "acp permission request id");
	}

	static function tool(name:String):McpToolInfo {
		return {
			name: name,
			description: '${name} tool',
			inputSchema: Unknown.fromBoundary({type: "object"}),
		};
	}

	static function prompt(name:String):McpPromptInfo {
		return {name: name, description: '${name} prompt'};
	}

	static function resource(name:String, uri:String):McpResourceInfo {
		return {
			name: name,
			uri: uri,
			description: '${name} resource',
			mimeType: "text/markdown"
		};
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}

class SmokeMcpFixture {
	public final clients = new Map<String, FakeMcpClient>();
	public final failed = new Map<String, Bool>();
	public final needsAuth = new Map<String, Bool>();
	public var createCount(default, null):Int = 0;
	public final factory:McpClientFactory;

	public function new() {
		factory = create;
	}

	public function client(name:String, tools:Array<McpToolInfo>, prompts:Array<McpPromptInfo>, resources:Array<McpResourceInfo>):FakeMcpClient {
		final client = new FakeMcpClient(tools, prompts, resources);
		clients.set(name, client);
		return client;
	}

	function create(name:String, _config:opencodehx.mcp.McpRuntime.McpServerConfig):McpClient {
		createCount++;
		if (failed.exists(name))
			throw 'failed ${name}';
		if (needsAuth.exists(name))
			throw new McpNeedsAuth('auth ${name}');
		final client = clients.get(name);
		if (client == null)
			throw 'missing fake client ${name}';
		return client;
	}
}

class FakeMcpClient {
	public var toolDefs:Array<McpToolInfo>;

	final promptDefs:Array<McpPromptInfo>;
	final resourceDefs:Array<McpResourceInfo>;
	final handlers:Array<Void->Void> = [];

	public var listToolsCalls(default, null):Int = 0;
	public var closed(default, null):Bool = false;

	public function new(tools:Array<McpToolInfo>, prompts:Array<McpPromptInfo>, resources:Array<McpResourceInfo>) {
		this.toolDefs = tools;
		this.promptDefs = prompts;
		this.resourceDefs = resources;
	}

	public function listTools():Array<McpToolInfo> {
		listToolsCalls++;
		return toolDefs.copy();
	}

	public function listPrompts():Array<McpPromptInfo> {
		return promptDefs.copy();
	}

	public function listResources():Array<McpResourceInfo> {
		return resourceDefs.copy();
	}

	public function onToolsChanged(handler:Void->Void):Void {
		handlers.push(handler);
	}

	public function close():Void {
		closed = true;
	}

	public function triggerToolsChanged():Void {
		for (handler in handlers)
			handler();
	}
}

class SmokeAcpConnection {
	public final updates:Array<AcpSessionUpdate> = [];
	public final permissionRequests:Array<AcpPermissionRequest> = [];
	public final permissionReplies:Array<AcpPermissionReply> = [];

	public function new() {}

	public function sessionUpdate(update:AcpSessionUpdate):Void {
		updates.push(update);
	}

	public function requestPermission(request:AcpPermissionRequest):AcpPermissionDecision {
		permissionRequests.push(request);
		return {outcome: AcpPermissionOutcome.Allow};
	}

	public function permissionReply(reply:AcpPermissionReply):Void {
		permissionReplies.push(reply);
	}

	public function agentChunks(sessionID:String):Array<String> {
		final chunks:Array<String> = [];
		for (update in updates) {
			if (update.sessionID != sessionID)
				continue;
			switch update.update {
				case AgentMessageChunk(text):
					chunks.push(text);
				case PermissionRequest(_):
			}
		}
		return chunks;
	}
}
