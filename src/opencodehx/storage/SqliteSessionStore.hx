package opencodehx.storage;

import haxe.Json;
import opencodehx.host.node.BetterSqlite;
import opencodehx.session.MessageCodec;
import opencodehx.session.MessageID;
import opencodehx.session.MessageTypes.Cursor;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.WithParts;
import opencodehx.session.PartID;
import opencodehx.session.SessionID;
import opencodehx.session.SessionInfo.ProjectInfo;
import opencodehx.session.SessionInfo.SessionInfo;
import opencodehx.storage.SessionStore.MessagePage;
import opencodehx.storage.StorageError.StorageException;

class SqliteSessionStore implements SessionStore {
	final sql:BetterSqlite;

	public function new(path:String) {
		sql = new BetterSqlite(path);
		sql.pragma("foreign_keys = ON");
		sql.pragma("busy_timeout = 5000");
		createSchema();
	}

	public function close():Void {
		sql.close();
	}

	public function upsertProject(project:ProjectInfo):Void {
		sql.run("insert into project (id, name, worktree) values (?, ?, ?) on conflict(id) do update set name = excluded.name, worktree = excluded.worktree",
			[project.id, optionalField(project, "name"), project.worktree,]);
	}

	public function migrateGlobalSessions(worktree:String, projectID:String):Int {
		if (projectID == "global" || worktree == "")
			return 0;
		return sql.run("update session set project_id = ? where project_id = ? and directory = ?", [projectID, "global", worktree]);
	}

	public function createSession(info:SessionInfo):Void {
		insertOrReplaceSession(info);
	}

	public function getSession(id:SessionID):SessionInfo {
		final row = sql.get("select * from session where id = ?", [id.toString()]);
		if (row == null)
			throw new StorageException(NotFound('Session not found: ${id.toString()}'));
		return sessionFromRow(row);
	}

	public function updateSession(info:SessionInfo):Void {
		final changed = insertOrReplaceSession(info);
		if (changed == 0)
			throw new StorageException(NotFound('Session not found: ${info.id.toString()}'));
	}

	public function deleteSession(id:SessionID):Void {
		sql.run("delete from session where id = ?", [id.toString()]);
	}

	public function upsertMessage(info:Info):Void {
		final record = MessageCodec.encodeInfoRecord(info);
		final id = requiredString(record, "id");
		final sessionID = requiredString(record, "sessionID");
		final time = Reflect.field(Reflect.field(record, "time"), "created");
		Reflect.deleteField(record, "id");
		Reflect.deleteField(record, "sessionID");
		sql.run("insert into message (id, session_id, time_created, time_updated, data) values (?, ?, ?, ?, ?) on conflict(id) do update set data = excluded.data, time_updated = excluded.time_updated",
			[id, sessionID, time, time, Json.stringify(record)],);
	}

	public function removeMessage(sessionID:SessionID, messageID:MessageID):Void {
		sql.run("delete from message where id = ? and session_id = ?", [messageID.toString(), sessionID.toString()]);
	}

	public function upsertPart(part:Part, time:Float):Void {
		final record = MessageCodec.encodePartRecord(part);
		final id = requiredString(record, "id");
		final sessionID = requiredString(record, "sessionID");
		final messageID = requiredString(record, "messageID");
		Reflect.deleteField(record, "id");
		Reflect.deleteField(record, "sessionID");
		Reflect.deleteField(record, "messageID");
		sql.run("insert into part (id, message_id, session_id, time_created, time_updated, data) values (?, ?, ?, ?, ?, ?) on conflict(id) do update set data = excluded.data, time_updated = excluded.time_updated",
			[id, messageID, sessionID, time, time, Json.stringify(record)],);
	}

	public function removePart(sessionID:SessionID, messageID:MessageID, partID:PartID):Void {
		sql.run("delete from part where id = ? and message_id = ? and session_id = ?", [partID.toString(), messageID.toString(), sessionID.toString()]);
	}

	public function getPart(sessionID:SessionID, messageID:MessageID, partID:PartID):Null<Part> {
		final row = sql.get("select * from part where id = ? and message_id = ? and session_id = ?",
			[partID.toString(), messageID.toString(), sessionID.toString(),]);
		return row == null ? null : partFromRow(row);
	}

	public function pageMessages(sessionID:SessionID, limit:Int, ?before:String):MessagePage {
		final params:Array<Dynamic> = [sessionID.toString()];
		var where = "session_id = ?";
		if (before != null && before != "") {
			final cursor = MessageCodec.decodeCursor(before);
			where += " and (time_created < ? or (time_created = ? and id < ?))";
			params.push(cursor.time);
			params.push(cursor.time);
			params.push(cursor.id.toString());
		}
		params.push(limit + 1);

		final rows = sql.all('select * from message where ${where} order by time_created desc, id desc limit ?', params);
		if (rows.length == 0) {
			final session = sql.get("select id from session where id = ?", [sessionID.toString()]);
			if (session == null)
				throw new StorageException(NotFound('Session not found: ${sessionID.toString()}'));
			return {items: [], more: false};
		}

		final more = rows.length > limit;
		final slice = more ? rows.slice(0, limit) : rows;
		final items = hydrate(slice);
		items.reverse();
		final tail = slice[slice.length - 1];
		final result:Dynamic = {
			items: items,
			more: more,
		};
		if (more && tail != null) {
			final cursor:Cursor = {
				id: MessageID.make(requiredString(tail, "id")),
				time: requiredFloat(tail, "time_created"),
			};
			Reflect.setField(result, "cursor", MessageCodec.encodeCursor(cursor));
		}
		return cast result;
	}

	function hydrate(rows:Array<Dynamic>):Array<WithParts> {
		if (rows.length == 0)
			return [];

		final ids = rows.map(row -> requiredString(row, "id"));
		final placeholders = ids.map(_ -> "?").join(",");
		final partRows = sql.all('select * from part where message_id in (${placeholders}) order by message_id, time_created, id', cast ids);
		final partByMessage = new Map<String, Array<Part>>();
		for (row in partRows) {
			final messageID = requiredString(row, "message_id");
			final part = partFromRow(row);
			final list = mapGetParts(partByMessage, messageID);
			if (list == null) {
				partByMessage.set(messageID, [part]);
			} else {
				list.push(part);
			}
		}

		final hydrated:Array<WithParts> = [];
		for (row in rows) {
			final messageID = requiredString(row, "id");
			var parts:Array<Part> = [];
			final found = mapGetParts(partByMessage, messageID);
			if (found != null)
				parts = found;
			hydrated.push({
				info: infoFromRow(row),
				parts: parts,
			});
		}
		return hydrated;
	}

	function insertOrReplaceSession(info:SessionInfo):Int {
		return sql.run("insert into session (
				id, project_id, workspace_id, parent_id, slug, directory, title, version, share_url,
				summary_additions, summary_deletions, summary_files, summary_diffs, revert, permission,
				time_created, time_updated, time_compacting, time_archived
			) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
			on conflict(id) do update set
				project_id = excluded.project_id,
				workspace_id = excluded.workspace_id,
				parent_id = excluded.parent_id,
				slug = excluded.slug,
				directory = excluded.directory,
				title = excluded.title,
				version = excluded.version,
				share_url = excluded.share_url,
				summary_additions = excluded.summary_additions,
				summary_deletions = excluded.summary_deletions,
				summary_files = excluded.summary_files,
				summary_diffs = excluded.summary_diffs,
				revert = excluded.revert,
				permission = excluded.permission,
				time_created = excluded.time_created,
				time_updated = excluded.time_updated,
				time_compacting = excluded.time_compacting,
				time_archived = excluded.time_archived", [
			info.id.toString(),
			info.projectID,
			optionalField(info, "workspaceID"),
			optionalId(info, "parentID"),
			info.slug,
			info.directory,
			info.title,
			info.version,
			optionalNested(info, "share", "url"),
			optionalNested(info, "summary", "additions"),
			optionalNested(info, "summary", "deletions"),
			optionalNested(info, "summary", "files"),
			jsonOptional(optionalNested(info, "summary", "diffs")),
			jsonOptional(optionalField(info, "revert")),
			jsonOptional(optionalField(info, "permission")),
			info.time.created,
			info.time.updated,
			optionalNested(info, "time", "compacting"),
			optionalNested(info, "time", "archived"),
		],);
	}

	function infoFromRow(row:Dynamic):Info {
		final data = Json.parse(requiredString(row, "data"));
		Reflect.setField(data, "id", requiredString(row, "id"));
		Reflect.setField(data, "sessionID", requiredString(row, "session_id"));
		return MessageCodec.decodeInfoRecord(data, 'message:${requiredString(row, "id")}');
	}

	function partFromRow(row:Dynamic):Part {
		final data = Json.parse(requiredString(row, "data"));
		Reflect.setField(data, "id", requiredString(row, "id"));
		Reflect.setField(data, "sessionID", requiredString(row, "session_id"));
		Reflect.setField(data, "messageID", requiredString(row, "message_id"));
		return MessageCodec.decodePartRecord(data, 'part:${requiredString(row, "id")}');
	}

	function sessionFromRow(row:Dynamic):SessionInfo {
		final session:Dynamic = {
			id: SessionID.make(requiredString(row, "id")),
			slug: requiredString(row, "slug"),
			projectID: requiredString(row, "project_id"),
			directory: requiredString(row, "directory"),
			title: requiredString(row, "title"),
			version: requiredString(row, "version"),
			time: {
				created: requiredFloat(row, "time_created"),
				updated: requiredFloat(row, "time_updated"),
			},
		};
		copyRow(row, session, "workspace_id", "workspaceID");
		if (field(row, "parent_id") != null)
			Reflect.setField(session, "parentID", SessionID.make(field(row, "parent_id")));
		if (field(row, "share_url") != null)
			Reflect.setField(session, "share", {url: field(row, "share_url")});
		if (field(row, "summary_additions") != null || field(row, "summary_deletions") != null || field(row, "summary_files") != null) {
			final summary:Dynamic = {
				additions: intOrZero(field(row, "summary_additions")),
				deletions: intOrZero(field(row, "summary_deletions")),
				files: intOrZero(field(row, "summary_files")),
			};
			if (field(row, "summary_diffs") != null)
				Reflect.setField(summary, "diffs", Json.parse(field(row, "summary_diffs")));
			Reflect.setField(session, "summary", summary);
		}
		if (field(row, "revert") != null)
			Reflect.setField(session, "revert", Json.parse(field(row, "revert")));
		if (field(row, "permission") != null)
			Reflect.setField(session, "permission", Json.parse(field(row, "permission")));
		if (field(row, "time_compacting") != null)
			Reflect.setField(session.time, "compacting", field(row, "time_compacting"));
		if (field(row, "time_archived") != null)
			Reflect.setField(session.time, "archived", field(row, "time_archived"));
		return cast session;
	}

	function createSchema():Void {
		sql.exec("
			create table if not exists project (
				id text primary key,
				name text,
				worktree text not null
			);

			create table if not exists session (
				id text primary key,
				project_id text not null references project(id) on delete cascade,
				workspace_id text,
				parent_id text references session(id) on delete cascade,
				slug text not null,
				directory text not null,
				title text not null,
				version text not null,
				share_url text,
				summary_additions integer,
				summary_deletions integer,
				summary_files integer,
				summary_diffs text,
				revert text,
				permission text,
				time_created integer not null,
				time_updated integer not null,
				time_compacting integer,
				time_archived integer
			);

			create index if not exists session_project_idx on session(project_id);
			create index if not exists session_workspace_idx on session(workspace_id);
			create index if not exists session_parent_idx on session(parent_id);

			create table if not exists message (
				id text primary key,
				session_id text not null references session(id) on delete cascade,
				time_created integer not null,
				time_updated integer not null,
				data text not null
			);

			create index if not exists message_session_time_created_id_idx on message(session_id, time_created, id);

			create table if not exists part (
				id text primary key,
				message_id text not null references message(id) on delete cascade,
				session_id text not null,
				time_created integer not null,
				time_updated integer not null,
				data text not null
			);

			create index if not exists part_message_id_id_idx on part(message_id, id);
			create index if not exists part_session_idx on part(session_id);
		");
	}

	static function field(data:Dynamic, name:String):Dynamic {
		return Reflect.field(data, name);
	}

	static function copyRow(from:Dynamic, to:Dynamic, rowField:String, outField:String):Void {
		final value = field(from, rowField);
		if (value != null)
			Reflect.setField(to, outField, value);
	}

	static function requiredString(data:Dynamic, name:String):String {
		final value = field(data, name);
		if (value == null)
			throw new StorageException(InvalidRow(name, ['${name}: expected string']));
		return Std.string(value);
	}

	static function requiredFloat(data:Dynamic, name:String):Float {
		final value = field(data, name);
		if (value == null)
			throw new StorageException(InvalidRow(name, ['${name}: expected number']));
		return cast value;
	}

	static function optionalField(data:Dynamic, name:String):Dynamic {
		return Reflect.hasField(data, name) ? Reflect.field(data, name) : null;
	}

	static function optionalId(data:Dynamic, name:String):Dynamic {
		final value = optionalField(data, name);
		return value == null ? null : Std.string(value);
	}

	static function optionalNested(data:Dynamic, objectName:String, fieldName:String):Dynamic {
		final object = optionalField(data, objectName);
		if (object == null)
			return null;
		return optionalField(object, fieldName);
	}

	static function jsonOptional(value:Dynamic):Dynamic {
		return value == null ? null : Json.stringify(value);
	}

	static function intOrZero(value:Dynamic):Int {
		return value == null ? 0 : Std.int(value);
	}

	static function mapGetParts(map:Map<String, Array<Part>>, key:String):Null<Array<Part>> {
		return map.exists(key) ? map.get(key) : null;
	}
}
