package opencodehx.sync;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import opencodehx.host.node.BetterSqlite;
import opencodehx.sync.SyncEventStore.SyncPersistence;
import opencodehx.sync.SyncEventStore.SyncStoredEvent;

typedef SyncEventJsonCodec<T> = {
	final encode:T->String;
	final decode:String->T;
}

class SyncSqliteEventPersistence<T> {
	final sql:BetterSqlite;
	final codec:SyncEventJsonCodec<T>;

	public function new(path:String, codec:SyncEventJsonCodec<T>) {
		sql = new BetterSqlite(path);
		this.codec = codec;
		sql.pragma("foreign_keys = ON");
		sql.pragma("busy_timeout = 5000");
		createSchema();
	}

	public function close():Void {
		sql.close();
	}

	public function persistence():SyncPersistence<T> {
		return {
			load: load,
			save: save,
			remove: remove,
		};
	}

	public function load():Array<SyncStoredEvent<T>> {
		return sql.all("select id, type, seq, aggregate_id, data from event order by aggregate_id, seq, id").map(row -> rowToEvent(row));
	}

	public function save(event:SyncStoredEvent<T>):Void {
		sql.transaction(() -> {
			sql.run("insert into event_sequence (aggregate_id, seq) values (?, ?) on conflict(aggregate_id) do update set seq = excluded.seq",
				[event.aggregateID, event.seq,]);
			sql.run("insert into event (id, aggregate_id, seq, type, data) values (?, ?, ?, ?, ?)",
				[event.id, event.aggregateID, event.seq, event.type, codec.encode(event.data),]);
		});
	}

	public function remove(aggregateID:String):Void {
		sql.transaction(() -> {
			sql.run("delete from event_sequence where aggregate_id = ?", [aggregateID]);
		});
	}

	public function persistedSeq(aggregateID:String):Null<Int> {
		final row = sql.get("select seq from event_sequence where aggregate_id = ?", [aggregateID]);
		if (row == null)
			return null;
		return requiredInt(rowRecord(Unknown.fromBoundary(row)), "seq");
	}

	public function persistedEventCount(?aggregateID:String):Int {
		final row = aggregateID == null ? sql.get("select count(*) as count from event") : sql.get("select count(*) as count from event where aggregate_id = ?",
			[aggregateID]);
		return requiredInt(rowRecord(Unknown.fromBoundary(row)), "count");
	}

	function createSchema():Void {
		sql.exec("
			create table if not exists event_sequence (
				aggregate_id text not null primary key,
				seq integer not null
			);

			create table if not exists event (
				id text primary key,
				aggregate_id text not null references event_sequence(aggregate_id) on delete cascade,
				seq integer not null,
				type text not null,
				data text not null
			);

			create index if not exists event_aggregate_seq_idx on event(aggregate_id, seq);
		");
	}

	function rowToEvent(row:Unknown):SyncStoredEvent<T> {
		// SQLite rows are schema-dependent JS objects at the host boundary; this
		// decoder immediately narrows the event columns before returning domain data.
		final record = rowRecord(row);
		return {
			id: requiredString(record, "id"),
			type: requiredString(record, "type"),
			seq: requiredInt(record, "seq"),
			aggregateID: requiredString(record, "aggregate_id"),
			data: codec.decode(requiredString(record, "data")),
		};
	}

	static function rowRecord(row:Unknown):UnknownRecord {
		final record = UnknownNarrow.record(row);
		if (record == null)
			throw "sync sqlite row: expected object";
		return record;
	}

	static function requiredString(row:UnknownRecord, name:String):String {
		final value = UnknownNarrow.string(row.get(name));
		if (value == null)
			throw 'sync sqlite row ${name}: expected string';
		return value;
	}

	static function requiredInt(row:UnknownRecord, name:String):Int {
		final value = UnknownNarrow.int32(row.get(name));
		if (value == null)
			throw 'sync sqlite row ${name}: expected integer';
		return value;
	}
}
