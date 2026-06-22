package opencodehx.mcp;

import genes.ts.Unknown;
import haxe.DynamicAccess;

typedef McpServerConfig = {
	final type:String;
	@:optional final command:Array<String>;
	@:optional final url:String;
	@:optional final enabled:Bool;
	@:optional final oauth:Bool;
	@:optional final headers:DynamicAccess<String>;
	@:optional final timeout:Int;
}

typedef McpStatus = {
	final status:String;
	@:optional final error:String;
}

typedef McpToolInfo = {
	final name:String;
	@:optional final description:String;
	final inputSchema:Unknown;
}

typedef McpPromptInfo = {
	final name:String;
	@:optional final description:String;
}

typedef McpResourceInfo = {
	final name:String;
	final uri:String;
	@:optional final description:String;
	@:optional final mimeType:String;
}

typedef McpTransportOptions = {
	@:optional final requestInit:{final headers:DynamicAccess<String>;};
	@:optional final authProvider:Bool;
}

typedef McpAddResult = {
	final status:DynamicAccess<McpStatus>;
}

typedef McpClient = {
	function listTools():Array<McpToolInfo>;
	function listPrompts():Array<McpPromptInfo>;
	function listResources():Array<McpResourceInfo>;
	function onToolsChanged(handler:Void->Void):Void;
	function close():Void;
}

typedef McpClientFactory = (String, McpServerConfig) -> McpClient;

class McpRuntime {
	final factory:McpClientFactory;
	final configured = new Map<String, McpServerConfig>();
	final clients = new Map<String, McpClient>();
	final statuses = new Map<String, McpStatus>();
	final toolDefs = new Map<String, Array<McpToolInfo>>();

	public function new(factory:McpClientFactory) {
		this.factory = factory;
	}

	public function add(name:String, config:McpServerConfig):McpAddResult {
		configured.set(name, config);
		if (config.enabled == false) {
			replaceClient(name, null);
			statuses.set(name, {status: "disabled"});
			toolDefs.remove(name);
			return {status: status()};
		}
		try {
			final client = factory(name, config);
			replaceClient(name, client);
			refreshTools(name, client);
			client.onToolsChanged(() -> refreshTools(name, client));
			statuses.set(name, {status: "connected"});
		} catch (error:McpNeedsAuth) {
			replaceClient(name, null);
			toolDefs.remove(name);
			statuses.set(name, {status: "needs_auth"});
		} catch (error:Dynamic) {
			replaceClient(name, null);
			toolDefs.remove(name);
			statuses.set(name, {status: "failed", error: Std.string(error)});
		}
		return {status: status()};
	}

	public function connect(name:String):Void {
		final config = configured.get(name);
		if (config == null)
			return;
		add(name, config);
	}

	public function disconnect(name:String):Void {
		if (!configured.exists(name) && !clients.exists(name))
			return;
		replaceClient(name, null);
		statuses.set(name, {status: "disabled"});
		toolDefs.remove(name);
	}

	public function status():DynamicAccess<McpStatus> {
		final out = new DynamicAccess<McpStatus>();
		for (name in statuses.keys())
			out.set(name, statuses.get(name));
		return out;
	}

	public function tools():DynamicAccess<McpToolInfo> {
		final out = new DynamicAccess<McpToolInfo>();
		for (server in sortedKeys(toolDefs)) {
			final status = statuses.get(server);
			if (status == null || status.status != "connected")
				continue;
			final cachedTools = toolDefs.get(server);
			if (cachedTools == null)
				continue;
			for (tool in cachedTools) {
				out.set(prefixed(server, tool.name), tool);
			}
		}
		return out;
	}

	public function prompts():DynamicAccess<McpPromptInfo> {
		final out = new DynamicAccess<McpPromptInfo>();
		for (server in sortedKeys(clients)) {
			if (!connected(server))
				continue;
			final client = clients.get(server);
			if (client == null)
				continue;
			for (prompt in client.listPrompts()) {
				out.set(prefixed(server, prompt.name), prompt);
			}
		}
		return out;
	}

	public function resources():DynamicAccess<McpResourceInfo> {
		final out = new DynamicAccess<McpResourceInfo>();
		for (server in sortedKeys(clients)) {
			if (!connected(server))
				continue;
			final client = clients.get(server);
			if (client == null)
				continue;
			for (resource in client.listResources()) {
				out.set(prefixed(server, resource.name), resource);
			}
		}
		return out;
	}

	public static function transportOptions(config:McpServerConfig):McpTransportOptions {
		// MCP SDK transport options are a third-party constructor boundary with
		// optional fields. Keep this open only while assembling the exact object
		// shape; callers receive the typed facade immediately.
		final out:Dynamic = {};
		if (config.headers != null)
			Reflect.setField(out, "requestInit", {headers: config.headers});
		if (config.oauth != false)
			Reflect.setField(out, "authProvider", true);
		return cast out;
	}

	function refreshTools(name:String, client:McpClient):Void {
		toolDefs.set(name, client.listTools());
	}

	function replaceClient(name:String, next:Null<McpClient>):Void {
		final existing = clients.get(name);
		if (existing != null)
			existing.close();
		clients.remove(name);
		if (next != null)
			clients.set(name, next);
	}

	function connected(name:String):Bool {
		final status = statuses.get(name);
		return status != null && status.status == "connected";
	}

	static function sortedKeys<T>(map:Map<String, T>):Array<String> {
		final keys:Array<String> = [];
		for (key in map.keys())
			keys.push(key);
		keys.sort(Reflect.compare);
		return keys;
	}

	static function prefixed(server:String, name:String):String {
		return sanitize(server) + "_" + sanitize(name);
	}

	static function sanitize(value:String):String {
		final out = new StringBuf();
		for (index in 0...value.length) {
			final ch = value.charAt(index);
			final code = ch.charCodeAt(0);
			final ok = (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || ch == "_" || ch == "-";
			out.add(ok ? ch : "_");
		}
		return out.toString();
	}
}
