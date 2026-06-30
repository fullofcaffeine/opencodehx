package opencodehx.lsp;

import genes.ts.Unknown;
import opencodehx.externs.node.Url;
import opencodehx.lsp.LspTypes.LspEndpoint;
import opencodehx.lsp.LspTypes.LspInitializeException;
import opencodehx.lsp.LspTypes.LspServerHandle;
import opencodehx.lsp.LspTypes.LspWorkspaceFolder;

class LspClient {
	public final serverID:String;
	public final root:String;
	public final endpoint:LspEndpoint;
	public final diagnostics = new LspDiagnostics();

	final directory:String;
	var closed = false;

	public function new(serverID:String, root:String, directory:String, handle:LspServerHandle) {
		this.serverID = serverID;
		this.root = root;
		this.directory = directory;
		endpoint = handle.endpoint;
		endpoint.setClientRequestHandler(handleServerRequest);
		final workspaceFolders = [workspaceFolder(root)];
		final initialized = endpoint.initialize({
			rootUri: workspaceFolders[0].uri,
			processId: handle.processId == null ? 0 : handle.processId,
			workspaceFolders: workspaceFolders,
		});
		if (!initialized.ok) {
			final reason = initialized.timeout == true ? "timeout" : initialized.error != null ? initialized.error : "failed";
			throw new LspInitializeException('${serverID} initialize ${reason}');
		}
		endpoint.sendNotification("initialized", Unknown.fromBoundary({}));
	}

	public function sendRequest(method:String, params:Unknown):Unknown {
		final result = endpoint.sendRequest(method, params);
		if (!result.ok) {
			final reason = result.timeout == true ? "timeout" : result.error != null ? result.error : "failed";
			throw new LspInitializeException('${serverID} request ${method} ${reason}');
		}
		return result.value == null ? Unknown.fromBoundary(null) : result.value;
	}

	public function sendNotification(method:String, params:Unknown):Void {
		endpoint.sendNotification(method, params);
	}

	public function shutdown():Void {
		if (closed)
			return;
		closed = true;
		endpoint.shutdown();
	}

	function handleServerRequest(method:String):Unknown {
		return switch method {
			case "workspace/workspaceFolders":
				Unknown.fromBoundary([workspaceFolder(root)]);
			case "window/workDoneProgress/create" | "workspace/configuration" | "client/registerCapability" | "client/unregisterCapability":
				Unknown.fromBoundary(null);
			case _:
				Unknown.fromBoundary(null);
		}
	}

	function workspaceFolder(path:String):LspWorkspaceFolder {
		return {name: "workspace", uri: Url.pathToFileURL(path).href};
	}
}
