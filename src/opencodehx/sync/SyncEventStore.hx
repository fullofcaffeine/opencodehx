package opencodehx.sync;

using StringTools;

typedef SyncDefinition<T> = {
	final type:String;
	final version:Int;
	final aggregate:T->String;
	@:optional final aggregateName:String;
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

typedef SyncProjection<T> = {
	final definition:SyncDefinition<T>;
	final project:SyncStoredEvent<T>->Void;
}

typedef SyncBusEvent<T> = {
	final type:String;
	final properties:T;
}

typedef SyncGlobalPayload<T> = {
	final type:String;
	final syncEvent:SyncStoredEvent<T>;
}

typedef SyncGlobalEvent<T> = {
	final directory:String;
	final project:String;
	final workspace:String;
	final payload:SyncGlobalPayload<T>;
}

typedef SyncPayloadDescriptor = {
	final type:String;
	final name:String;
	final aggregate:String;
}

typedef SyncEventSystemInit<T> = {
	final projectors:Array<SyncProjection<T>>;
	@:optional final convertEvent:T->T;
	@:optional final directory:String;
	@:optional final project:String;
	@:optional final workspace:String;
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

class SyncEventSystem<T> {
	final registry:Map<String, SyncDefinition<T>> = new Map();
	final latestVersions:Map<String, Int> = new Map();
	final stores:Map<String, SyncEventStore<T>> = new Map();
	var projectors:Null<Map<String, SyncStoredEvent<T>->Void>> = null;
	var convertEvent:T->T = data -> data;
	var directory:String = "";
	var project:String = "";
	var workspace:String = "";
	var frozen = false;

	public final busEvents:Array<SyncBusEvent<T>> = [];
	public final globalEvents:Array<SyncGlobalEvent<T>> = [];

	public function new() {}

	public function reset():Void {
		registry.clear();
		latestVersions.clear();
		stores.clear();
		projectors = null;
		convertEvent = data -> data;
		directory = "";
		project = "";
		workspace = "";
		frozen = false;
		busEvents.resize(0);
		globalEvents.resize(0);
	}

	public function define(definition:SyncDefinition<T>):SyncDefinition<T> {
		if (frozen)
			throw "Error defining sync event: sync system has been frozen";
		final versioned = SyncEventStore.versionedType(definition);
		registry.set(versioned, definition);
		final current = latestVersions.exists(definition.type) ? latestVersions.get(definition.type) : 0;
		if (definition.version > current)
			latestVersions.set(definition.type, definition.version);
		return definition;
	}

	public function init(input:SyncEventSystemInit<T>):Void {
		final installed = new Map<String, SyncStoredEvent<T>->Void>();
		for (projection in input.projectors) {
			installed.set(SyncEventStore.versionedType(projection.definition), projection.project);
		}
		projectors = installed;
		convertEvent = input.convertEvent == null ? data->data : input.convertEvent;
		directory = input.directory == null ? "" : input.directory;
		project = input.project == null ? "" : input.project;
		workspace = input.workspace == null ? "" : input.workspace;
		frozen = true;
	}

	public function run(definition:SyncDefinition<T>, data:T, ?publish:Bool):SyncStoredEvent<T> {
		final latest = latestVersions.exists(definition.type) ? latestVersions.get(definition.type) : definition.version;
		if (definition.version != latest)
			throw 'SyncEvent.run: running old versions of events is not allowed: ${definition.type}';
		final projector = projectorFor(definition);
		final event = store(definition).run(data, false);
		process(definition, event, publish != false, projector);
		return event;
	}

	public function replay(event:SyncStoredEvent<T>, ?publish:Bool):Void {
		final definition = registry.get(event.type);
		if (definition == null)
			throw 'Unknown event type: ${event.type}';
		final projector = projectorFor(definition);
		store(definition).replay(event, false);
		process(definition, event, publish == true, projector);
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

	public function payloads():Array<SyncPayloadDescriptor> {
		final result:Array<SyncPayloadDescriptor> = [];
		for (type in registry.keys()) {
			final definition = registry.get(type);
			if (definition != null) {
				result.push({
					type: "sync",
					name: type,
					aggregate: definition.aggregateName == null ? "aggregateID" : definition.aggregateName,
				});
			}
		}
		result.sort((left, right) -> Reflect.compare(left.name, right.name));
		return result;
	}

	public function history(definition:SyncDefinition<T>, ?aggregateID:String):Array<SyncStoredEvent<T>> {
		return store(definition).history(aggregateID);
	}

	function process(definition:SyncDefinition<T>, event:SyncStoredEvent<T>, publish:Bool, projector:SyncStoredEvent<T>->Void):Void {
		projector(event);
		if (publish) {
			final converted = convertEvent(event.data);
			busEvents.push({type: definition.type, properties: converted});
			globalEvents.push({
				directory: directory,
				project: project,
				workspace: workspace,
				payload: {
					type: "sync",
					syncEvent: event,
				},
			});
		}
	}

	function projectorFor(definition:SyncDefinition<T>):SyncStoredEvent<T>->Void {
		if (projectors == null)
			throw "No projectors available. Call `SyncEvent.init` to install projectors";
		final projector = projectors.get(SyncEventStore.versionedType(definition));
		if (projector == null)
			throw 'Projector not found for event: ${definition.type}';
		return projector;
	}

	function store(definition:SyncDefinition<T>):SyncEventStore<T> {
		final versioned = SyncEventStore.versionedType(definition);
		if (!stores.exists(versioned)) {
			stores.set(versioned, new SyncEventStore<T>(definition));
		}
		return stores.get(versioned);
	}
}
