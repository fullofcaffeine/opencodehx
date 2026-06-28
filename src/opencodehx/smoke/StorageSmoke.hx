package opencodehx.smoke;

import haxe.DynamicAccess;
import haxe.Json;
import genes.ts.JsonCodec;
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
import opencodehx.storage.JsonStorageMigrationRuntime;
import opencodehx.storage.SqliteSessionStore;
import opencodehx.storage.StorageDatabasePath;
import opencodehx.storage.StorageError.StorageException;
import opencodehx.storage.StorageJsonRuntime;

class StorageSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-storage-"));
		final dbPath = NodePath.join(root, "opencodehx.db");
		final store = new SqliteSessionStore(dbPath);
		try {
			databasePath(root);
			jsonKeyValueStorage(root);
			store.upsertProject({id: "proj_fixture", worktree: root, name: "Fixture"});
			sessionCreateReadUpdate(store, root);
			messagePageAndPartCrud(store);
			jsonMigration(root);
			store.close();
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			store.close();
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function jsonKeyValueStorage(root:String):Void {
		final storage = new StorageJsonRuntime(NodePath.join(root, "json-kv"));
		final roundtrip = ["roundtrip", "value"];
		storage.write(roundtrip, genes.ts.Json.value([{file: "a.ts", additions: 2, deletions: 1}]));
		eq(jsonString(storage.read(roundtrip)), '[{"file":"a.ts","additions":2,"deletions":1}]', "storage json roundtrip");

		expectNotFound(() -> storage.read(["missing", "value"]), "storage missing read");
		expectNotFound(() -> storage.update(["missing", "key"], _ -> genes.ts.Json.value({value: 1})), "storage missing update");

		final overwrite = ["overwrite", "test"];
		storage.write(overwrite, genes.ts.Json.value({v: 1}));
		storage.write(overwrite, genes.ts.Json.value({v: 2}));
		eq(jsonString(storage.read(overwrite)), '{"v":2}', "storage overwrite");

		final update = ["counter", "shared"];
		storage.write(update, genes.ts.Json.value({value: 0}));
		storage.update(update, _ -> genes.ts.Json.value({value: 1}));
		eq(jsonString(storage.read(update)), '{"value":1}', "storage update");

		final deep = ["a", "b", "c", "deep"];
		storage.write(deep, genes.ts.Json.value({nested: true}));
		eq(jsonString(storage.read(deep)), '{"nested":true}', "storage nested read");
		eq(keys(storage.list(["a"])), "a/b/c/deep", "storage nested list");

		final a = ["list", "a"];
		final b = ["list", "b"];
		storage.write(b, genes.ts.Json.value({value: 2}));
		storage.write(a, genes.ts.Json.value({value: 1}));
		eq(keys(storage.list(["list"])), "list/a,list/b", "storage list sorted");
		storage.remove(a);
		eq(keys(storage.list(["list"])), "list/b", "storage remove listed key");
		expectNotFound(() -> storage.read(a), "storage removed read");
		storage.remove(["does", "not", "exist"]);
		eq(storage.list(["does"]).length, 0, "storage missing prefix empty");
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

		store.createSession(session("ses_store_old", root, "Old title", 1, 2));
		store.createSession(session("ses_store_new", root, "New title", 3, 30));
		final sessions = store.listSessions(3);
		eq(sessions.length, 3, "session list length");
		eq(sessions[0].id.toString(), "ses_store_new", "session list newest first");
		eq(sessions[1].id.toString(), "ses_store", "session list second newest");
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

	static function jsonMigration(root:String):Void {
		final store = new SqliteSessionStore(NodePath.join(root, "json-migration.db"));
		final storageDir = NodePath.join(root, "legacy-storage");
		setupLegacyStorage(storageDir);
		writeJson(join3(storageDir, "project", "proj_filename.json"), {
			id: "proj_stale",
			worktree: "/test/path",
			name: "Filename Project",
			sandboxes: [],
		});
		writeJson(join4(storageDir, "session", "proj_filename", "ses_from_filename.json"), {
			id: "ses_stale",
			projectID: "proj_stale",
			slug: "legacy-session",
			directory: "/test/path",
			title: "Legacy Session",
			version: "1.0.0",
			time: {created: 1700000000000, updated: 1700000001000},
		});
		writeJson(join4(storageDir, "message", "ses_from_filename", "msg_from_filename.json"), {
			id: "msg_stale",
			sessionID: "ses_stale",
			role: "user",
			agent: "default",
			model: {providerID: "openai", modelID: "gpt-4"},
			time: {created: 1700000000000},
		});
		writeJson(join4(storageDir, "part", "msg_from_filename", "prt_from_filename.json"), {
			id: "prt_stale",
			messageID: "msg_stale",
			type: "text",
			text: "Hello, migration!",
		});
		writeJson(join3(storageDir, "todo", "ses_from_filename.json"), [
			{content: "First todo", status: "pending", priority: "high"},
			{content: "Skipped todo", priority: "low"},
			{content: "Second todo", status: "completed", priority: "medium"},
		]);
		writeJson(join3(storageDir, "todo", "ses_missing.json"), [{content: "Orphan todo", status: "pending", priority: "high"}]);
		writeJson(join3(storageDir, "permission", "proj_filename.json"), [
			{permission: "file.read", pattern: "/test/file1.ts", action: "allow"},
			{permission: "file.write", pattern: "/test/file2.ts", action: "ask"},
		]);
		writeJson(join3(storageDir, "permission", "proj_missing.json"), [{permission: "file.write", pattern: "*", action: "deny"}]);
		writeJson(join3(storageDir, "session_share", "ses_from_filename.json"), {
			id: "share_123",
			secret: "supersecretkey",
			url: "https://share.example.com/ses_from_filename",
		});
		writeJson(join3(storageDir, "session_share", "ses_missing.json"), {
			id: "share_missing",
			secret: "secret",
			url: "https://missing.example.com",
		});

		final stats = JsonStorageMigrationRuntime.run(storageDir, store);
		eq(stats.projects, 1, "json migration project count");
		eq(stats.sessions, 1, "json migration session count");
		eq(stats.messages, 1, "json migration message count");
		eq(stats.parts, 1, "json migration part count");
		eq(stats.todos, 2, "json migration todo count");
		eq(stats.todoItems.length, 2, "json migration todo item count");
		eq(stats.todoItems[0].content, "First todo", "json migration first todo content");
		eq(stats.todoItems[0].position, 0, "json migration first todo position");
		eq(stats.todoItems[1].content, "Second todo", "json migration second todo content");
		eq(stats.todoItems[1].position, 2, "json migration second todo position preserves source index");
		eq(stats.permissions, 1, "json migration permission count");
		eq(stats.permissionFiles[0].projectID, "proj_filename", "json migration permission project id");
		eq(stats.permissionFiles[0].rules, 2, "json migration permission rule count");
		eq(stats.shares, 1, "json migration share count");
		eq(stats.shareItems[0].sessionID, "ses_from_filename", "json migration share session id");
		eq(stats.shareItems[0].url, "https://share.example.com/ses_from_filename", "json migration share url");
		eq(stats.errors.length, 0, "json migration errors");

		final sessionID = SessionID.make("ses_from_filename");
		final migrated = store.getSession(sessionID);
		eq(migrated.projectID, "proj_filename", "json migration uses session directory project id");
		eq(migrated.title, "Legacy Session", "json migration session title");

		final page = store.pageMessages(sessionID, 10);
		eq(page.items.length, 1, "json migration message page length");
		eq(messageID(page.items[0].info), "msg_from_filename", "json migration uses message filename id");
		final part = store.getPart(sessionID, MessageID.make("msg_from_filename"), PartID.make("prt_from_filename"));
		if (part == null)
			throw "json migration part lookup: expected part";
		eq(text(part), "Hello, migration!", "json migration part text");

		JsonStorageMigrationRuntime.run(storageDir, store);
		eq(store.pageMessages(sessionID, 10).items.length, 1, "json migration rerun is idempotent");

		final orphanDir = NodePath.join(root, "legacy-orphan");
		setupLegacyStorage(orphanDir);
		writeJson(join4(orphanDir, "session", "proj_missing", "ses_orphan.json"), {
			id: "ses_orphan",
			projectID: "proj_missing",
			slug: "orphan",
			directory: "/",
			title: "Orphan",
			version: "1.0.0",
			time: {created: 1, updated: 2},
		});
		eq(JsonStorageMigrationRuntime.run(orphanDir, store).sessions, 0, "json migration skips orphan session");
		eq(JsonStorageMigrationRuntime.run(NodePath.join(root, "missing-storage"), store).projects, 0, "json migration missing dir");
		store.close();
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

	static function setupLegacyStorage(storageDir:String):Void {
		for (dir in ["project", "session", "message", "part", "todo", "permission", "session_share"]) {
			Fs.mkdirSync(NodePath.join(storageDir, dir), {recursive: true});
		}
		Fs.mkdirSync(join3(storageDir, "session", "proj_filename"), {recursive: true});
		Fs.mkdirSync(join3(storageDir, "session", "proj_missing"), {recursive: true});
		Fs.mkdirSync(join3(storageDir, "message", "ses_from_filename"), {recursive: true});
		Fs.mkdirSync(join3(storageDir, "part", "msg_from_filename"), {recursive: true});
	}

	static function writeJson<T>(path:String, value:T):Void {
		Fs.writeFileSync(path, Json.stringify(value));
	}

	static function jsonString(value:genes.ts.JsonValue):String {
		return JsonCodec.stringify(value);
	}

	static function keys(values:Array<Array<String>>):String {
		return [for (value in values) value.join("/")].join(",");
	}

	static function join3(first:String, second:String, third:String):String {
		return NodePath.join(NodePath.join(first, second), third);
	}

	static function join4(first:String, second:String, third:String, fourth:String):String {
		return NodePath.join(join3(first, second, third), fourth);
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
