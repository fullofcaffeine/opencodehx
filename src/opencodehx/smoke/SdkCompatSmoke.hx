package opencodehx.smoke;

import genes.js.Async.await;
import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.sdk.OpenCodeCompatClient;
import opencodehx.server.OpenCodeServer;
import opencodehx.server.ServerTypes.ServerListener;

class SdkCompatSmoke {
	@:async
	public static function run():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-sdk-"));
		final server = new OpenCodeServer({
			directory: root,
			dbPath: NodePath.join(root, "opencodehx.db"),
		});
		var listener:Null<ServerListener> = null;
		try {
			listener = @:await server.listen(0, "127.0.0.1");
			final client = new OpenCodeCompatClient({baseUrl: listener.url, directory: root, workspace: "wrk_sdk"});
			final events = client.events(3);
			final created = @:await client.createSession({prompt: "SDK compatible prompt", title: "SDK fixture"});
			eq(created.id, "ses_server_1", "sdk create session id");
			eq(created.title, "SDK fixture", "sdk create session title");
			eq(created.directory, root, "sdk create session directory");
			final listed = @:await client.listSessions(10);
			eq(listed.length, 1, "sdk list session count");
			eq(listed[0].id, created.id, "sdk list session id");
			final received = @:await events;
			eq(received[0].type, "server.connected", "sdk event connected");
			eq(hasSessionCreated(received, created.id), true, "sdk event session created");
			@:await listener.stop(true);
			server.close();
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			if (listener != null)
				@:await listener.stop(true);
			server.close();
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function hasSessionCreated(events:Array<opencodehx.server.ServerProtocol.ServerEvent>, sessionID:String):Bool {
		for (event in events) {
			if (event.type == "session.created" && event.properties.sessionID == sessionID)
				return true;
		}
		return false;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
