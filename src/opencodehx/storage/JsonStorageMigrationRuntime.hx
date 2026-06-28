package opencodehx.storage;

import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.Json;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.session.MessageCodec;
import opencodehx.session.MessageID;
import opencodehx.session.PartID;
import opencodehx.session.SessionID;
import opencodehx.session.SessionInfo.ProjectInfo;
import opencodehx.session.SessionInfo.SessionInfo;
import opencodehx.storage.SessionStore;

typedef JsonStorageMigrationStats = {
	var projects:Int;
	var sessions:Int;
	var messages:Int;
	var parts:Int;
	var todos:Int;
	var permissions:Int;
	var shares:Int;
	var todoItems:Array<JsonStorageMigratedTodo>;
	var permissionFiles:Array<JsonStorageMigratedPermission>;
	var shareItems:Array<JsonStorageMigratedShare>;
	var errors:Array<String>;
}

typedef JsonStorageMigratedTodo = {
	final sessionID:String;
	final content:String;
	final status:String;
	final priority:String;
	final position:Int;
}

typedef JsonStorageMigratedPermission = {
	final projectID:String;
	final rules:Int;
}

typedef JsonStorageMigratedShare = {
	final sessionID:String;
	final id:String;
	final secret:String;
	final url:String;
}

/**
	Focused migration runtime for legacy JSON storage files.

	Upstream migrates a larger Drizzle schema including todos, permissions,
	session shares, and detailed unreadable-file error reporting. The current
	OpenCodeHX store only owns project/session/message/part persistence, so this
	runtime migrates that compatible subset and preserves the key upstream rule:
	path-derived IDs win over stale IDs embedded inside JSON bodies.
**/
class JsonStorageMigrationRuntime {
	public static function run(storageDir:String, store:SessionStore):JsonStorageMigrationStats {
		final stats = emptyStats();
		if (!Fs.existsSync(storageDir))
			return stats;

		final projects = migrateProjects(storageDir, store);
		stats.projects = projects.count;
		final sessions = migrateSessions(storageDir, store, projects.ids);
		stats.sessions = sessions.count;
		final messages = migrateMessages(storageDir, store);
		stats.messages = messages.count;
		stats.parts = migrateParts(storageDir, store, messages.sessionByMessage);
		final todos = migrateTodos(storageDir, sessions.ids);
		stats.todos = todos.count;
		stats.todoItems = todos.items;
		final permissions = migratePermissions(storageDir, projects.ids);
		stats.permissions = permissions.count;
		stats.permissionFiles = permissions.items;
		final shares = migrateShares(storageDir, sessions.ids);
		stats.shares = shares.count;
		stats.shareItems = shares.items;
		return stats;
	}

	static function migrateProjects(storageDir:String, store:SessionStore):ProjectMigrationResult {
		final ids = new Map<String, Bool>();
		var count = 0;
		final dir = NodePath.join(storageDir, "project");
		if (!Fs.existsSync(dir))
			return {count: count, ids: ids};
		for (file in jsonFiles(dir)) {
			final id = jsonID(file);
			final record = readRecord(NodePath.join(dir, file));
			final project:ProjectInfo = {
				id: id,
				worktree: stringOr(record, "worktree", ""),
				name: optionalString(record, "name"),
			};
			store.upsertProject(project);
			ids.set(id, true);
			count++;
		}
		return {count: count, ids: ids};
	}

	static function migrateSessions(storageDir:String, store:SessionStore, projectIDs:Map<String, Bool>):SessionMigrationResult {
		var count = 0;
		final ids = new Map<String, Bool>();
		final dir = NodePath.join(storageDir, "session");
		if (!Fs.existsSync(dir))
			return {count: count, ids: ids};
		for (projectDir in childDirectories(dir)) {
			if (!projectIDs.exists(projectDir))
				continue;
			final projectPath = NodePath.join(dir, projectDir);
			for (file in jsonFiles(projectPath)) {
				final record = readRecord(NodePath.join(projectPath, file));
				final session = sessionFromRecord(record, jsonID(file), projectDir);
				store.createSession(session);
				ids.set(session.id.toString(), true);
				count++;
			}
		}
		return {count: count, ids: ids};
	}

	static function migrateMessages(storageDir:String, store:SessionStore):MessageMigrationResult {
		var count = 0;
		final sessionByMessage = new Map<String, String>();
		final dir = NodePath.join(storageDir, "message");
		if (!Fs.existsSync(dir))
			return {count: count, sessionByMessage: sessionByMessage};
		for (sessionDir in childDirectories(dir)) {
			final sessionID = SessionID.make(sessionDir);
			for (file in jsonFiles(NodePath.join(dir, sessionDir))) {
				final messageID = jsonID(file);
				final record = readRecord(join3(dir, sessionDir, file));
				final message = MessageCodec.decodeInfoRecord({
					id: messageID,
					sessionID: sessionID.toString(),
					role: stringOr(record, "role", "user"),
					time: createdTime(record),
					agent: stringOr(record, "agent", "default"),
					model: modelSelection(record),
				}, 'legacy-message:${messageID}');
				store.upsertMessage(message);
				sessionByMessage.set(messageID, sessionID.toString());
				count++;
			}
		}
		return {count: count, sessionByMessage: sessionByMessage};
	}

	static function migrateParts(storageDir:String, store:SessionStore, sessionByMessage:Map<String, String>):Int {
		var count = 0;
		final dir = NodePath.join(storageDir, "part");
		if (!Fs.existsSync(dir))
			return count;
		for (messageDir in childDirectories(dir)) {
			for (file in jsonFiles(NodePath.join(dir, messageDir))) {
				final record = readRecord(join3(dir, messageDir, file));
				final sessionID = stringOr(record, "sessionID", sessionByMessage.exists(messageDir) ? sessionByMessage.get(messageDir) : "unknown-session");
				final part = MessageCodec.decodePartRecord({
					id: jsonID(file),
					sessionID: sessionID,
					messageID: messageDir,
					type: stringOr(record, "type", "text"),
					text: stringOr(record, "text", ""),
				}, 'legacy-part:${jsonID(file)}');
				store.upsertPart(part, numberOr(record, "time", 0));
				count++;
			}
		}
		return count;
	}

	static function migrateTodos(storageDir:String, sessionIDs:Map<String, Bool>):TodoMigrationResult {
		var count = 0;
		final items:Array<JsonStorageMigratedTodo> = [];
		final dir = NodePath.join(storageDir, "todo");
		if (!Fs.existsSync(dir))
			return {count: count, items: items};
		for (file in jsonFiles(dir)) {
			final sessionID = jsonID(file);
			if (!sessionIDs.exists(sessionID))
				continue;
			final todos = readArray(NodePath.join(dir, file));
			for (index in 0...todos.length) {
				final record = UnknownNarrow.record(todos.get(index));
				if (record == null)
					continue;
				final content = optionalString(record, "content");
				final status = optionalString(record, "status");
				final priority = optionalString(record, "priority");
				if (content == null || status == null || priority == null)
					continue;
				items.push({
					sessionID: sessionID,
					content: content,
					status: status,
					priority: priority,
					position: index,
				});
				count++;
			}
		}
		return {count: count, items: items};
	}

	static function migratePermissions(storageDir:String, projectIDs:Map<String, Bool>):PermissionMigrationResult {
		var count = 0;
		final items:Array<JsonStorageMigratedPermission> = [];
		final dir = NodePath.join(storageDir, "permission");
		if (!Fs.existsSync(dir))
			return {count: count, items: items};
		for (file in jsonFiles(dir)) {
			final projectID = jsonID(file);
			if (!projectIDs.exists(projectID))
				continue;
			final rules = readArray(NodePath.join(dir, file));
			items.push({
				projectID: projectID,
				rules: rules.length,
			});
			count++;
		}
		return {count: count, items: items};
	}

	static function migrateShares(storageDir:String, sessionIDs:Map<String, Bool>):ShareMigrationResult {
		var count = 0;
		final items:Array<JsonStorageMigratedShare> = [];
		final dir = NodePath.join(storageDir, "session_share");
		if (!Fs.existsSync(dir))
			return {count: count, items: items};
		for (file in jsonFiles(dir)) {
			final sessionID = jsonID(file);
			if (!sessionIDs.exists(sessionID))
				continue;
			final record = readRecord(NodePath.join(dir, file));
			final id = optionalString(record, "id");
			final secret = optionalString(record, "secret");
			final url = optionalString(record, "url");
			if (id == null || secret == null || url == null)
				continue;
			items.push({
				sessionID: sessionID,
				id: id,
				secret: secret,
				url: url,
			});
			count++;
		}
		return {count: count, items: items};
	}

	static function sessionFromRecord(record:UnknownRecord, id:String, projectID:String):SessionInfo {
		return {
			id: SessionID.make(id),
			projectID: projectID,
			slug: stringOr(record, "slug", id),
			directory: stringOr(record, "directory", ""),
			title: stringOr(record, "title", ""),
			version: stringOr(record, "version", "0.0.0"),
			time: timeRange(record),
		};
	}

	static function timeRange(record:UnknownRecord):opencodehx.session.SessionInfo.SessionTime {
		final time = UnknownNarrow.record(record.get("time"));
		return {
			created: time == null ? 0 : numberOr(time, "created", 0),
			updated: time == null ? 0 : numberOr(time, "updated", 0),
		};
	}

	static function createdTime(record:UnknownRecord):opencodehx.session.MessageTypes.CreatedTime {
		final time = UnknownNarrow.record(record.get("time"));
		return {
			created: time == null ? 0 : numberOr(time, "created", 0),
		};
	}

	static function modelSelection(record:UnknownRecord):opencodehx.session.MessageTypes.UserModelSelection {
		final model = UnknownNarrow.record(record.get("model"));
		return {
			providerID: model == null ? "test" : stringOr(model, "providerID", "test"),
			modelID: model == null ? "test-model" : stringOr(model, "modelID", "test-model"),
		};
	}

	static function readRecord(path:String):UnknownRecord {
		final raw = Unknown.fromBoundary(Json.parse(Fs.readFileSync(path, "utf8")));
		final record = UnknownNarrow.record(raw);
		if (record == null)
			throw 'legacy JSON storage file is not an object: ${path}';
		return record;
	}

	static function readArray(path:String):UnknownArray {
		final raw = Unknown.fromBoundary(Json.parse(Fs.readFileSync(path, "utf8")));
		final array = UnknownNarrow.array(raw);
		if (array == null)
			throw 'legacy JSON storage file is not an array: ${path}';
		return array;
	}

	static function jsonFiles(dir:String):Array<String> {
		return Fs.readdirNamesSync(dir).filter(file -> StringTools.endsWith(file, ".json"));
	}

	static function childDirectories(dir:String):Array<String> {
		return Fs.readdirNamesSync(dir).filter(name -> Fs.statSync(NodePath.join(dir, name)).isDirectory());
	}

	static function jsonID(file:String):String {
		return file.substr(0, file.length - ".json".length);
	}

	static function join3(first:String, second:String, third:String):String {
		return NodePath.join(NodePath.join(first, second), third);
	}

	static function optionalString(record:UnknownRecord, field:String):Null<String> {
		return UnknownNarrow.string(record.get(field));
	}

	static function stringOr(record:UnknownRecord, field:String, fallback:String):String {
		final value = optionalString(record, field);
		return value == null ? fallback : value;
	}

	static function numberOr(record:UnknownRecord, field:String, fallback:Float):Float {
		final value = UnknownNarrow.number(record.get(field));
		return value == null ? fallback : value;
	}

	static function emptyStats():JsonStorageMigrationStats {
		return {
			projects: 0,
			sessions: 0,
			messages: 0,
			parts: 0,
			todos: 0,
			permissions: 0,
			shares: 0,
			todoItems: [],
			permissionFiles: [],
			shareItems: [],
			errors: [],
		};
	}
}

private typedef ProjectMigrationResult = {
	final count:Int;
	final ids:Map<String, Bool>;
}

private typedef SessionMigrationResult = {
	final count:Int;
	final ids:Map<String, Bool>;
}

private typedef MessageMigrationResult = {
	final count:Int;
	final sessionByMessage:Map<String, String>;
}

private typedef TodoMigrationResult = {
	final count:Int;
	final items:Array<JsonStorageMigratedTodo>;
}

private typedef PermissionMigrationResult = {
	final count:Int;
	final items:Array<JsonStorageMigratedPermission>;
}

private typedef ShareMigrationResult = {
	final count:Int;
	final items:Array<JsonStorageMigratedShare>;
}
