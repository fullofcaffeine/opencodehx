package opencodehx.smoke;

import genes.js.Async.await;
import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.sdk.OpenCodeCompatClient;
import opencodehx.session.MessageTypes.Info;
import opencodehx.server.OpenCodeServer;
import opencodehx.server.ServerProtocol.ServerEventTypes;
import opencodehx.server.ServerProtocol.SessionStatusType;
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
			eq(@:await client.selectSession(created.id), true, "sdk select session");
			final full = @:await client.messages(created.id);
			eq(full.items.length, 2, "sdk resume full message count");
			eq(messageID(full.items[0].info), "msg_user_one_ses_server_1", "sdk resume full first message");
			eq(messageID(full.items[1].info), "msg_assistant_one_ses_server_1", "sdk resume full second message");
			final firstPage = @:await client.messages(created.id, 1);
			eq(firstPage.items.length, 1, "sdk resume first page count");
			eq(messageID(firstPage.items[0].info), "msg_assistant_one_ses_server_1", "sdk resume first page newest message");
			eq(firstPage.cursor != null, true, "sdk resume cursor");
			eq(firstPage.link != null && firstPage.link.indexOf('rel="next"') != -1, true, "sdk resume link header");
			final cursor = firstPage.cursor;
			if (cursor == null)
				throw "sdk resume cursor missing";
			final secondPage = @:await client.messages(created.id, 1, cursor);
			eq(secondPage.items.length, 1, "sdk resume second page count");
			eq(messageID(secondPage.items[0].info), "msg_user_one_ses_server_1", "sdk resume second page older message");
			final received = @:await events;
			eq(received[0].type, ServerEventTypes.known("server.connected"), "sdk event connected");
			eq(hasSessionStatus(received, created.id, SessionStatusType.Busy), true, "sdk event session busy");
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
			if (event.type == ServerEventTypes.known("session.created") && event.properties.sessionID == sessionID)
				return true;
		}
		return false;
	}

	static function hasSessionStatus(events:Array<opencodehx.server.ServerProtocol.ServerEvent>, sessionID:String, status:SessionStatusType):Bool {
		for (event in events) {
			final eventStatus = event.properties.status;
			if (event.type == ServerEventTypes.known("session.status")
				&& event.properties.sessionID == sessionID
				&& eventStatus != null
				&& eventStatus.type == status)
				return true;
		}
		return false;
	}

	static function messageID(info:Info):String {
		return switch info {
			case UserInfo(data):
				data.id.toString();
			case AssistantInfo(data):
				data.id.toString();
		}
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
