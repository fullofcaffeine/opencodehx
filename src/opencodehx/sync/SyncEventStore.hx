package opencodehx.sync;

using StringTools;

typedef SyncDefinition<T> = {
	final type:String;
	final version:Int;
	final aggregate:T->String;
}

typedef SyncStoredEvent<T> = {
	final id:String;
	final type:String;
	final seq:Int;
	final aggregateID:String;
	final data:T;
}

typedef SyncKnownSeq = {
	final aggregateID:String;
	final seq:Int;
}

typedef SyncPersistence<T> = {
	final load:Void->Array<SyncStoredEvent<T>>;
	final save:SyncStoredEvent<T>->Void;
	final remove:String->Void;
}

typedef SyncEventStoreOptions<T> = {
	@:optional final persistence:SyncPersistence<T>;
	@:optional final publisher:SyncStoredEvent<T>->Void;
}

class SyncEventStore<T> {
	final definition:SyncDefinition<T>;
	final rows:Array<SyncStoredEvent<T>> = [];
	final persistence:Null<SyncPersistence<T>>;
	final publisher:Null<SyncStoredEvent<T>->Void>;
	var nextID:Int = 1;

	public function new(definition:SyncDefinition<T>, ?options:SyncEventStoreOptions<T>) {
		this.definition = definition;
		persistence = options == null ? null : options.persistence;
		publisher = options == null ? null : options.publisher;
		if (persistence != null) {
			for (event in persistence.load()) {
				rows.push(event);
				advanceNextID(event.id);
			}
		}
	}

	public function run(data:T, ?publish:Bool):SyncStoredEvent<T> {
		final aggregateID = definition.aggregate(data);
		if (aggregateID == "")
			throw 'SyncEvent.run: aggregate required for ${definition.type}';
		final event:SyncStoredEvent<T> = {
			id: 'evt_${nextID++}',
			type: versionedType(definition),
			seq: latest(aggregateID) + 1,
			aggregateID: aggregateID,
			data: data,
		};
		append(event, publish != false);
		return event;
	}

	public function replay(event:SyncStoredEvent<T>, ?publish:Bool):Void {
		if (event.type != versionedType(definition))
			throw 'Unknown event type: ${event.type}';
		final current = latest(event.aggregateID);
		if (event.seq <= current)
			return;
		final expected = current + 1;
		if (event.seq != expected)
			throw 'Sequence mismatch for aggregate "${event.aggregateID}": expected ${expected}, got ${event.seq}';
		append(event, publish == true);
	}

	public function replayAll(events:Array<SyncStoredEvent<T>>, ?publish:Bool):Null<String> {
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
			replay(event, publish == true);
		return source;
	}

	public function history(?aggregateID:String):Array<SyncStoredEvent<T>> {
		if (aggregateID == null)
			return rows.copy();
		return rows.filter(event -> event.aggregateID == aggregateID);
	}

	public function historyAfter(knownSeqs:Array<SyncKnownSeq>):Array<SyncStoredEvent<T>> {
		final out:Array<SyncStoredEvent<T>> = [];
		for (event in rows) {
			final known = knownSeq(knownSeqs, event.aggregateID);
			if (event.seq > known)
				out.push(event);
		}
		out.sort((left, right) -> left.seq - right.seq);
		return out;
	}

	public function remove(aggregateID:String):Void {
		var index = rows.length - 1;
		while (index >= 0) {
			if (rows[index].aggregateID == aggregateID)
				rows.splice(index, 1);
			index -= 1;
		}
		if (persistence != null)
			persistence.remove(aggregateID);
	}

	function append(event:SyncStoredEvent<T>, publish:Bool):Void {
		rows.push(event);
		advanceNextID(event.id);
		if (persistence != null)
			persistence.save(event);
		if (publish && publisher != null)
			publisher(event);
	}

	function latest(aggregateID:String):Int {
		var out = -1;
		for (event in rows) {
			if (event.aggregateID == aggregateID && event.seq > out)
				out = event.seq;
		}
		return out;
	}

	static function knownSeq(knownSeqs:Array<SyncKnownSeq>, aggregateID:String):Int {
		for (item in knownSeqs) {
			if (item.aggregateID == aggregateID)
				return item.seq;
		}
		return -1;
	}

	function advanceNextID(id:String):Void {
		if (!id.startsWith("evt_"))
			return;
		final parsed = Std.parseInt(id.substr(4));
		if (parsed != null && parsed >= nextID)
			nextID = parsed + 1;
	}

	public static function versionedType<T>(definition:SyncDefinition<T>):String {
		return '${definition.type}.${definition.version}';
	}
}
