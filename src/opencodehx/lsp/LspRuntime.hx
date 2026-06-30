package opencodehx.lsp;

import genes.ts.Unknown;
import opencodehx.host.node.NodePath;
import opencodehx.lsp.LspTypes.LspLocationInput;
import opencodehx.lsp.LspTypes.LspRuntimeContext;
import opencodehx.lsp.LspTypes.LspRuntimeOptions;
import opencodehx.lsp.LspTypes.LspServerDefinition;
import opencodehx.lsp.LspTypes.LspStatus;

class LspRuntime {
	final directory:String;
	final worktree:String;
	final servers:Array<LspServerDefinition>;
	final clients:Array<LspClient> = [];
	final broken = new Map<String, Bool>();

	public function new(options:LspRuntimeOptions) {
		directory = NodePath.normalize(options.directory);
		worktree = NodePath.normalize(options.worktree == null ? options.directory : options.worktree);
		servers = [];
		if (options.enabled) {
			final disabled = options.disabled == null ? [] : options.disabled;
			final configured = options.servers == null ? [typescriptServer(null)] : options.servers;
			for (server in configured) {
				if (disabled.indexOf(server.id) == -1)
					servers.push(server);
			}
		}
	}

	public static function typescriptServer(?spawn:(String, LspRuntimeContext) -> Null<opencodehx.lsp.LspTypes.LspServerHandle>):LspServerDefinition {
		return {
			id: "typescript",
			extensions: [".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".mts", ".cts"],
			root: function(file, ctx) {
				if (hasAncestorMarker(file, ctx.directory, ["deno.json", "deno.jsonc"]))
					return null;
				return ctx.directory;
			},
			spawn: spawn == null ? function(_root, _ctx) return null : spawn,
		};
	}

	public function init():Void {}

	public function status():Array<LspStatus> {
		final out:Array<LspStatus> = [];
		for (client in clients) {
			out.push({
				id: client.serverID,
				name: client.serverID,
				root: NodePath.relative(directory, client.root),
				status: "connected",
			});
		}
		return out;
	}

	public function hasClients(file:String):Bool {
		final normalized = absolute(file);
		if (!contains(directory, normalized) && (worktree == "/" || !contains(worktree, normalized)))
			return false;
		final extension = NodePath.extname(normalized);
		final ctx = context();
		for (server in servers) {
			if (server.extensions.length > 0 && server.extensions.indexOf(extension) == -1)
				continue;
			final root = server.root(normalized, ctx);
			if (root == null)
				continue;
			if (!broken.exists(root + server.id))
				return true;
		}
		return false;
	}

	public function touchFile(file:String, ?waitForDiagnostics:Bool):Void {
		ensureClients(file);
	}

	public function diagnostics():LspDiagnostics {
		final out = new LspDiagnostics();
		for (client in clients)
			out.mergeFrom(client.diagnostics);
		return out;
	}

	public function hover(input:LspLocationInput):Array<Unknown> {
		return requestEach(input, "textDocument/hover");
	}

	public function definition(input:LspLocationInput):Array<Unknown> {
		return requestEach(input, "textDocument/definition");
	}

	public function references(input:LspLocationInput):Array<Unknown> {
		return requestEach(input, "textDocument/references");
	}

	public function implementation(input:LspLocationInput):Array<Unknown> {
		return requestEach(input, "textDocument/implementation");
	}

	public function documentSymbol(uri:String):Array<Unknown> {
		final out:Array<Unknown> = [];
		for (client in clients)
			out.push(client.sendRequest("textDocument/documentSymbol", Unknown.fromBoundary({textDocument: {uri: uri}})));
		return out;
	}

	public function workspaceSymbol(query:String):Array<Unknown> {
		final out:Array<Unknown> = [];
		for (client in clients)
			out.push(client.sendRequest("workspace/symbol", Unknown.fromBoundary({query: query})));
		return out;
	}

	public function prepareCallHierarchy(input:LspLocationInput):Array<Unknown> {
		return requestEach(input, "textDocument/prepareCallHierarchy");
	}

	public function incomingCalls(input:LspLocationInput):Array<Unknown> {
		return requestEach(input, "callHierarchy/incomingCalls");
	}

	public function outgoingCalls(input:LspLocationInput):Array<Unknown> {
		return requestEach(input, "callHierarchy/outgoingCalls");
	}

	public function shutdown():Void {
		for (client in clients)
			client.shutdown();
		clients.resize(0);
	}

	function ensureClients(file:String):Array<LspClient> {
		final normalized = absolute(file);
		final out:Array<LspClient> = [];
		if (!contains(directory, normalized) && (worktree == "/" || !contains(worktree, normalized)))
			return out;
		final extension = NodePath.extname(normalized);
		final ctx = context();
		for (server in servers) {
			if (server.extensions.length > 0 && server.extensions.indexOf(extension) == -1)
				continue;
			final root = server.root(normalized, ctx);
			if (root == null)
				continue;
			final key = root + server.id;
			if (broken.exists(key))
				continue;
			final existing = findClient(server.id, root);
			if (existing != null) {
				out.push(existing);
				continue;
			}
			final handle = server.spawn(root, ctx);
			if (handle == null) {
				broken.set(key, true);
				continue;
			}
			try {
				final client = new LspClient(server.id, root, directory, handle);
				clients.push(client);
				out.push(client);
			} catch (error:haxe.Exception) {
				broken.set(key, true);
				handle.endpoint.shutdown();
			}
		}
		return out;
	}

	function requestEach(input:LspLocationInput, method:String):Array<Unknown> {
		final clients = ensureClients(input.file);
		final out:Array<Unknown> = [];
		for (client in clients) {
			out.push(client.sendRequest(method, Unknown.fromBoundary({
				textDocument: {uri: opencodehx.externs.node.Url.pathToFileURL(input.file).href},
				position: {line: input.line, character: input.character},
			})));
		}
		return out;
	}

	function findClient(serverID:String, root:String):Null<LspClient> {
		for (client in clients) {
			if (client.serverID == serverID && client.root == root)
				return client;
		}
		return null;
	}

	function context():LspRuntimeContext {
		return {directory: directory, worktree: worktree};
	}

	function absolute(file:String):String {
		return NodePath.normalize(NodePath.isAbsolute(file) ? file : NodePath.resolve(directory, file));
	}

	static function contains(root:String, file:String):Bool {
		final rel = NodePath.relative(root, file);
		return rel == "" || (!StringTools.startsWith(rel, "..") && !NodePath.isAbsolute(rel));
	}

	static function hasAncestorMarker(file:String, stop:String, names:Array<String>):Bool {
		var dir = NodePath.dirname(file);
		while (contains(stop, dir)) {
			for (name in names) {
				if (opencodehx.externs.node.Fs.existsSync(NodePath.join(dir, name)))
					return true;
			}
			final next = NodePath.dirname(dir);
			if (next == dir)
				break;
			dir = next;
		}
		return false;
	}
}
