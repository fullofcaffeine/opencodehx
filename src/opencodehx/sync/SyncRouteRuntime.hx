package opencodehx.sync;

import genes.ts.Unknown;
import haxe.ds.StringMap;
import js.Syntax;

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
			switch decodeEvent(eventValues[index], 'events[${index}]') {
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

	static function arrayField(data:Unknown, name:String):Null<Array<Unknown>> {
		final value = field(data, name);
		if (value == null || !isArray(value))
			return null;
		return Syntax.code("({0} as Array<unknown>)", value);
	}

	static function stringField(data:Unknown, name:String):Null<String> {
		final value = field(data, name);
		if (value == null || !isString(value))
			return null;
		return Syntax.code("({0} as string)", value);
	}

	static function field(data:Unknown, name:String):Null<Unknown> {
		if (!hasField(data, name))
			return null;
		return Unknown.fromBoundary(Syntax.code("({0} as Record<string, unknown>)[{1}]", data, name));
	}

	static function hasField(data:Unknown, name:String):Bool {
		return Syntax.code("typeof {0} === 'object' && {0} !== null && !Array.isArray({0}) && Object.prototype.hasOwnProperty.call({0}, {1})", data, name);
	}

	static function objectKeys(data:Unknown):Array<String> {
		return Syntax.code("Object.keys({0} as Record<string, unknown>)", data);
	}

	static function isPlainObject(value:Null<Unknown>):Bool {
		return Syntax.code("typeof {0} === 'object' && {0} !== null && !Array.isArray({0})", value);
	}

	static function isArray(value:Null<Unknown>):Bool {
		return Syntax.code("Array.isArray({0})", value);
	}

	static function isString(value:Null<Unknown>):Bool {
		return Syntax.code("typeof {0} === 'string'", value);
	}

	static function isNonNegativeInteger(value:Null<Unknown>):Bool {
		return Syntax.code("typeof {0} === 'number' && Number.isInteger({0}) && {0} >= 0", value);
	}

	static function intValue(value:Null<Unknown>):Int {
		return Syntax.code("({0} as number)", value);
	}
}
