package opencodehx.sync;

import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import haxe.ds.StringMap;

typedef SyncRouteEvent = {
	final id:String;
	final type:String;
	final seq:Int;
	final aggregateID:String;
	final data:Unknown;
}

typedef SyncHistoryEvent = {
	final id:String;
	final type:String;
	final seq:Int;
	final aggregate_id:String;
	final data:Unknown;
}

typedef SyncRouteKnownSeq = {
	final aggregateID:String;
	final seq:Int;
}

typedef SyncReplayRequest = {
	final directory:String;
	final events:Array<SyncRouteEvent>;
}

enum SyncRouteDecode<T> {
	SyncDecoded(value:T);
	SyncRejected(message:String);
}

class SyncRouteRuntime {
	final rows:Array<SyncRouteEvent> = [];
	final knownTypes:StringMap<Bool> = new StringMap();
	final validatesTypes:Bool;

	public function new(?types:Array<String>) {
		validatesTypes = types != null && types.length > 0;
		if (types != null) {
			for (type in types)
				knownTypes.set(type, true);
		}
	}

	public function start():Bool {
		return true;
	}

	public function replayAll(events:Array<SyncRouteEvent>):Null<String> {
		if (events.length == 0)
			return null;
		final source = events[0].aggregateID;
		final start = events[0].seq;
		for (index in 0...events.length) {
			final event = events[index];
			if (event.aggregateID != source)
				throw "Replay events must belong to the same session";
			final expected = start + index;
			if (event.seq != expected)
				throw 'Replay sequence mismatch at index ${index}: expected ${expected}, got ${event.seq}';
		}
		for (event in events)
			replay(event);
		return source;
	}

	public function history(knownSeqs:Array<SyncRouteKnownSeq>):Array<SyncHistoryEvent> {
		final out:Array<SyncHistoryEvent> = [];
		for (event in rows) {
			final known = knownSeq(knownSeqs, event.aggregateID);
			if (event.seq > known)
				out.push(toHistory(event));
		}
		out.sort((left, right) -> left.seq - right.seq);
		return out;
	}

	function replay(event:SyncRouteEvent):Void {
		if (validatesTypes && !knownTypes.exists(event.type))
			throw 'Unknown event type: ${event.type}';
		final current = latest(event.aggregateID);
		if (event.seq <= current)
			return;
		final expected = current + 1;
		if (event.seq != expected)
			throw 'Sequence mismatch for aggregate "${event.aggregateID}": expected ${expected}, got ${event.seq}';
		rows.push(event);
	}

	function latest(aggregateID:String):Int {
		var out = -1;
		for (event in rows) {
			if (event.aggregateID == aggregateID && event.seq > out)
				out = event.seq;
		}
		return out;
	}

	static function knownSeq(knownSeqs:Array<SyncRouteKnownSeq>, aggregateID:String):Int {
		for (item in knownSeqs) {
			if (item.aggregateID == aggregateID)
				return item.seq;
		}
		return -1;
	}

	static function toHistory(event:SyncRouteEvent):SyncHistoryEvent {
		return {
			id: event.id,
			type: event.type,
			seq: event.seq,
			aggregate_id: event.aggregateID,
			data: event.data,
		};
	}

	public static function decodeReplay(raw:Unknown):SyncRouteDecode<SyncReplayRequest> {
		if (!isPlainObject(raw))
			return SyncRejected("sync replay body must be an object");
		final directory = stringField(raw, "directory");
		if (directory == null)
			return SyncRejected("directory: expected string");
		final eventValues = arrayField(raw, "events");
		if (eventValues == null || eventValues.length == 0)
			return SyncRejected("events: expected non-empty array");
		final events:Array<SyncRouteEvent> = [];
		for (index in 0...eventValues.length) {
			switch decodeEvent(eventValues.get(index), 'events[${index}]') {
				case SyncRejected(message):
					return SyncRejected(message);
				case SyncDecoded(event):
					events.push(event);
			}
		}
		return SyncDecoded({directory: directory, events: events});
	}

	public static function decodeHistory(raw:Unknown):SyncRouteDecode<Array<SyncRouteKnownSeq>> {
		if (!isPlainObject(raw))
			return SyncRejected("sync history body must be an object");
		final known:Array<SyncRouteKnownSeq> = [];
		for (key in objectKeys(raw)) {
			final value = field(raw, key);
			if (value == null || !isNonNegativeInteger(value))
				return SyncRejected('${key}: expected sequence number');
			known.push({
				aggregateID: key,
				seq: intValue(value),
			});
		}
		return SyncDecoded(known);
	}

	static function decodeEvent(raw:Unknown, path:String):SyncRouteDecode<SyncRouteEvent> {
		if (!isPlainObject(raw))
			return SyncRejected('${path}: expected object');
		final id = stringField(raw, "id");
		if (id == null)
			return SyncRejected('${path}.id: expected string');
		final type = stringField(raw, "type");
		if (type == null)
			return SyncRejected('${path}.type: expected string');
		final seqValue = field(raw, "seq");
		if (seqValue == null || !isNonNegativeInteger(seqValue))
			return SyncRejected('${path}.seq: expected non-negative integer');
		final aggregateID = stringField(raw, "aggregateID");
		if (aggregateID == null)
			return SyncRejected('${path}.aggregateID: expected string');
		final data = field(raw, "data");
		if (data == null || !isPlainObject(data))
			return SyncRejected('${path}.data: expected object');
		return SyncDecoded({
			id: id,
			type: type,
			seq: intValue(seqValue),
			aggregateID: aggregateID,
			data: data,
		});
	}

	static function arrayField(data:Unknown, name:String):Null<UnknownArray> {
		final value = field(data, name);
		return value == null ? null : UnknownNarrow.array(value);
	}

	static function stringField(data:Unknown, name:String):Null<String> {
		final value = field(data, name);
		return value == null ? null : UnknownNarrow.string(value);
	}

	static function field(data:Unknown, name:String):Null<Unknown> {
		final record = UnknownNarrow.record(data);
		return record == null || !record.hasOwn(name) ? null : record.get(name);
	}

	static function hasField(data:Unknown, name:String):Bool {
		final record = UnknownNarrow.record(data);
		return record != null && record.hasOwn(name);
	}

	static function objectKeys(data:Unknown):Array<String> {
		final record = UnknownNarrow.record(data);
		return record == null ? [] : record.keys();
	}

	static function isPlainObject(value:Null<Unknown>):Bool {
		return value != null && UnknownNarrow.record(value) != null;
	}

	static function isArray(value:Null<Unknown>):Bool {
		return value != null && UnknownNarrow.array(value) != null;
	}

	static function isString(value:Null<Unknown>):Bool {
		return value != null && UnknownNarrow.string(value) != null;
	}

	static function isNonNegativeInteger(value:Null<Unknown>):Bool {
		if (value == null)
			return false;
		final int = UnknownNarrow.int32(value);
		return int != null && int >= 0;
	}

	static function intValue(value:Null<Unknown>):Int {
		if (value == null)
			return 0;
		final int = UnknownNarrow.int32(value);
		return int == null ? 0 : int;
	}
}
