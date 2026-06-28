package opencodehx.storage;

import genes.ts.Unknown;
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
	var errors:Array<String>;
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
		stats.sessions = migrateSessions(storageDir, store, projects.ids);
		final messages = migrateMessages(storageDir, store);
		stats.messages = messages.count;
		stats.parts = migrateParts(storageDir, store, messages.sessionByMessage);
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

	static function migrateSessions(storageDir:String, store:SessionStore, projectIDs:Map<String, Bool>):Int {
		var count = 0;
		final dir = NodePath.join(storageDir, "session");
		if (!Fs.existsSync(dir))
			return count;
		for (projectDir in childDirectories(dir)) {
			if (!projectIDs.exists(projectDir))
				continue;
			final projectPath = NodePath.join(dir, projectDir);
			for (file in jsonFiles(projectPath)) {
				final record = readRecord(NodePath.join(projectPath, file));
				final session = sessionFromRecord(record, jsonID(file), projectDir);
				store.createSession(session);
				count++;
			}
		}
		return count;
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
			errors: [],
		};
	}
}

private typedef ProjectMigrationResult = {
	final count:Int;
	final ids:Map<String, Bool>;
}

private typedef MessageMigrationResult = {
	final count:Int;
	final sessionByMessage:Map<String, String>;
}
