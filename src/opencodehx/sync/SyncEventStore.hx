package opencodehx.sync;

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

class SyncEventStore<T> {
	final definition:SyncDefinition<T>;
	final rows:Array<SyncStoredEvent<T>> = [];
	var nextID:Int = 1;

	public function new(definition:SyncDefinition<T>) {
		this.definition = definition;
	}

	public function run(data:T):SyncStoredEvent<T> {
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
		rows.push(event);
		return event;
	}

	public function replay(event:SyncStoredEvent<T>):Void {
		if (event.type != versionedType(definition))
			throw 'Unknown event type: ${event.type}';
		final current = latest(event.aggregateID);
		if (event.seq <= current)
			return;
		final expected = current + 1;
		if (event.seq != expected)
			throw 'Sequence mismatch for aggregate "${event.aggregateID}": expected ${expected}, got ${event.seq}';
		rows.push(event);
	}

	public function replayAll(events:Array<SyncStoredEvent<T>>):Null<String> {
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

	public function history(?aggregateID:String):Array<SyncStoredEvent<T>> {
		if (aggregateID == null)
			return rows.copy();
		return rows.filter(event -> event.aggregateID == aggregateID);
	}

	function latest(aggregateID:String):Int {
		var out = -1;
		for (event in rows) {
			if (event.aggregateID == aggregateID && event.seq > out)
				out = event.seq;
		}
		return out;
	}

	static function versionedType<T>(definition:SyncDefinition<T>):String {
		return '${definition.type}.${definition.version}';
	}
}
