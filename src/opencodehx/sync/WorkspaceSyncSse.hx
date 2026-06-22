package opencodehx.sync;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.Json;
import opencodehx.sync.SyncRouteRuntime.SyncRouteEvent;

using StringTools;

typedef WorkspaceSyncPayload = {
	final type:String;
	final syncEvent:Null<SyncRouteEvent>;
	final properties:Null<Unknown>;
}

typedef WorkspaceSyncGlobalEvent = {
	final directory:Null<String>;
	final project:Null<String>;
	final workspace:Null<String>;
	final payload:WorkspaceSyncPayload;
}

typedef WorkspaceSyncFallbackMessage = {
	final data:String;
	final id:Null<String>;
	final retry:Int;
}

typedef WorkspaceSyncSseEvent = {
	final raw:String;
	final json:Null<Unknown>;
	final global:Null<WorkspaceSyncGlobalEvent>;
	final fallback:Null<WorkspaceSyncFallbackMessage>;
}

class WorkspaceSyncSse {
	public static function parse(text:String):Array<WorkspaceSyncSseEvent> {
		final events:Array<WorkspaceSyncSseEvent> = [];
		for (frame in frames(text)) {
			if (frame.data.length == 0)
				continue;
			final raw = frame.data.join("\n");
			final json = parseJson(raw);
			final global = json == null ? null : decodeGlobal(json);
			events.push({
				raw: raw,
				json: json,
				global: global,
				fallback: json == null ? {
					data: raw,
					id: frame.id,
					retry: frame.retry,
				} : null,
			});
		}
		return events;
	}

	static function parseJson(raw:String):Null<Unknown> {
		try {
			return Unknown.fromBoundary(Json.parse(raw));
		} catch (_:Dynamic) {
			return null;
		}
	}

	static function decodeGlobal(parsed:Unknown):Null<WorkspaceSyncGlobalEvent> {
		final record = UnknownNarrow.record(parsed);
		if (record == null || !record.hasOwn("payload"))
			return null;
		final payloadRecord = UnknownNarrow.record(record.get("payload"));
		if (payloadRecord == null)
			return null;
		final type = UnknownNarrow.string(payloadRecord.get("type"));
		if (type == null)
			return null;
		var syncEvent:Null<SyncRouteEvent> = null;
		if (payloadRecord.hasOwn("syncEvent")) {
			syncEvent = decodeSyncEvent(payloadRecord.get("syncEvent"));
		}
		return {
			directory: UnknownNarrow.string(record.get("directory")),
			project: UnknownNarrow.string(record.get("project")),
			workspace: UnknownNarrow.string(record.get("workspace")),
			payload: {
				type: type,
				syncEvent: syncEvent,
				properties: payloadRecord.hasOwn("properties") ? payloadRecord.get("properties") : null,
			},
		};
	}

	static function decodeSyncEvent(value:Unknown):Null<SyncRouteEvent> {
		final record = UnknownNarrow.record(value);
		if (record == null)
			return null;
		final id = UnknownNarrow.string(record.get("id"));
		final type = UnknownNarrow.string(record.get("type"));
		final aggregateID = UnknownNarrow.string(record.get("aggregateID"));
		final seq = UnknownNarrow.int32(record.get("seq"));
		final data = record.get("data");
		if (id == null || type == null || aggregateID == null || seq == null || UnknownNarrow.record(data) == null)
			return null;
		return {
			id: id,
			type: type,
			seq: seq,
			aggregateID: aggregateID,
			data: data,
		};
	}

	static function frames(text:String):Array<WorkspaceSyncFrame> {
		final normalized = text.replace("\r\n", "\n").replace("\r", "\n");
		final out:Array<WorkspaceSyncFrame> = [];
		var id:Null<String> = null;
		var retry = 1000;
		var data:Array<String> = [];

		function flush():Void {
			if (data.length > 0) {
				out.push({data: data.copy(), id: id, retry: retry});
				data.resize(0);
			}
		}

		for (line in normalized.split("\n")) {
			if (line == "") {
				flush();
				continue;
			}
			if (line.startsWith("data:")) {
				data.push(stripFieldValue(line.substr("data:".length)));
			} else if (line.startsWith("id:")) {
				id = stripFieldValue(line.substr("id:".length));
			} else if (line.startsWith("retry:")) {
				final parsed = Std.parseInt(stripFieldValue(line.substr("retry:".length)));
				if (parsed != null)
					retry = parsed;
			}
		}
		flush();
		return out;
	}

	static function stripFieldValue(value:String):String {
		return value.startsWith(" ") ? value.substr(1) : value;
	}
}

typedef WorkspaceSyncFrame = {
	final data:Array<String>;
	final id:Null<String>;
	final retry:Int;
}
