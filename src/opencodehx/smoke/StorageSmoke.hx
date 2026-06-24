package opencodehx.smoke;

import haxe.DynamicAccess;
import haxe.Json;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.GlobalPaths;
import opencodehx.host.node.NodePath;
import opencodehx.session.MessageCodec;
import opencodehx.session.MessageID;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.PartID;
import opencodehx.session.SessionID;
import opencodehx.session.SessionInfo.SessionInfo;
import opencodehx.storage.SqliteSessionStore;
import opencodehx.storage.StorageDatabasePath;
import opencodehx.storage.StorageError.StorageException;

class StorageSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-storage-"));
		final dbPath = NodePath.join(root, "opencodehx.db");
		final store = new SqliteSessionStore(dbPath);
		try {
			databasePath(root);
			store.upsertProject({id: "proj_fixture", worktree: root, name: "Fixture"});
			sessionCreateReadUpdate(store, root);
			messagePageAndPartCrud(store);
			store.close();
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			store.close();
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function databasePath(root:String):Void {
		final env = new DynamicAccess<String>();
		final dataRoot = NodePath.join(root, "xdg-data");
		env.set("XDG_DATA_HOME", dataRoot);
		final data = GlobalPaths.data(env);
		eq(StorageDatabasePath.getChannelPath(env, "latest"), NodePath.join(data, "opencode.db"), "storage latest db path");
		eq(StorageDatabasePath.getChannelPath(env, "beta"), NodePath.join(data, "opencode.db"), "storage beta db path");
		eq(StorageDatabasePath.getChannelPath(env, "prod"), NodePath.join(data, "opencode.db"), "storage prod db path");
		eq(StorageDatabasePath.getChannelPath(env, "dev/nightly"), NodePath.join(data, "opencode-dev-nightly.db"), "storage sanitized channel db path");
		eq(StorageDatabasePath.getChannelPath(env, "dev/nightly", true), NodePath.join(data, "opencode.db"), "storage disable channel db path");

		env.set("OPENCODE_DB", ":memory:");
		eq(StorageDatabasePath.path(env, "dev"), ":memory:", "storage memory db override");
		env.set("OPENCODE_DB", NodePath.join(root, "custom.db"));
		eq(StorageDatabasePath.path(env, "dev"), NodePath.join(root, "custom.db"), "storage absolute db override");
		env.set("OPENCODE_DB", "relative.db");
		eq(StorageDatabasePath.path(env, "dev"), NodePath.join(data, "relative.db"), "storage relative db override");
	}

	static function sessionCreateReadUpdate(store:SqliteSessionStore, root:String):Void {
		final info = session("ses_store", root, "Original title", 10, 11);
		store.createSession(info);
		eq(store.getSession(info.id).title, "Original title", "stored session title");

		final updated = session("ses_store", root, "Updated title", 10, 20);
		store.updateSession(updated);
		final found = store.getSession(info.id);
		eq(found.title, "Updated title", "updated session title");
		eq(found.time.updated, 20, "updated session time");
	}

	static function messagePageAndPartCrud(store:SqliteSessionStore):Void {
		final sessionID = SessionID.make("ses_store");
		for (index in 0...4) {
			final messageID = MessageID.make('msg_${index}');
			store.upsertMessage(userMessage(messageID, index + 1));
			store.upsertPart(textPart(PartID.make('prt_${index}'), messageID, 'm${index}'), index + 1);
		}

		final first = store.pageMessages(sessionID, 2);
		eq(first.more, true, "first page has more");
		eq(first.items.length, 2, "first page length");
		eq(messageID(first.items[0].info), "msg_2", "first page chronological head");
		eq(first.items[0].parts.length, 1, "hydrated part count");

		final second = store.pageMessages(sessionID, 2, first.cursor);
		eq(second.more, false, "second page exhausted");
		eq(second.items.length, 2, "second page length");
		eq(messageID(second.items[0].info), "msg_0", "second page chronological head");

		final part = store.getPart(sessionID, MessageID.make("msg_1"), PartID.make("prt_1"));
		if (part == null)
			throw "storage part lookup: expected part";
		eq(text(part), "m1", "part lookup text");

		store.removePart(sessionID, MessageID.make("msg_1"), PartID.make("prt_1"));
		eq(store.getPart(sessionID, MessageID.make("msg_1"), PartID.make("prt_1")), null, "part removed");

		store.deleteSession(sessionID);
		expectNotFound(() -> store.getSession(sessionID), "deleted session");
	}

	static function session(id:String, directory:String, title:String, created:Float, updated:Float):SessionInfo {
		return {
			id: SessionID.make(id),
			slug: "fixture-slug",
			projectID: "proj_fixture",
			directory: directory,
			title: title,
			version: "0.0.0-test",
			time: {
				created: created,
				updated: updated,
			},
		};
	}

	static function userMessage(id:MessageID, created:Float):Info {
		return MessageCodec.decodeInfoRecord({
			id: id.toString(),
			sessionID: "ses_store",
			role: "user",
			time: {created: created},
			agent: "test",
			model: {providerID: "test", modelID: "test-model"},
			tools: {},
		}, 'info:${id.toString()}');
	}

	static function textPart(id:PartID, messageID:MessageID, value:String):Part {
		return MessageCodec.decodePartRecord({
			id: id.toString(),
			sessionID: "ses_store",
			messageID: messageID.toString(),
			type: "text",
			text: value,
		}, 'part:${id.toString()}');
	}

	static function messageID(info:Info):String {
		return switch info {
			case UserInfo(userData):
				userData.id.toString();
			case AssistantInfo(assistantData):
				assistantData.id.toString();
		}
	}

	static function text(part:Part):String {
		return switch part {
			case TextPart(textData):
				textData.text;
			case _:
				throw "expected text part";
		}
	}

	static function expectNotFound(run:() -> Void, label:String):Void {
		try {
			run();
		} catch (error:StorageException) {
			if (isNotFound(error.failure))
				return;
		}
		throw '${label}: expected NotFoundError';
	}

	static function isNotFound(failure:opencodehx.storage.StorageError.StorageFailure):Bool {
		return switch failure {
			case NotFound(_):
				true;
			case _:
				false;
		}
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
