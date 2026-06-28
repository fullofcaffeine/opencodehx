package opencodehx.controlplane;

import genes.js.Async.await;
import genes.ts.Json;
import genes.ts.Unknown;
import js.lib.Promise;
import opencodehx.sync.SyncRouteRuntime;
import opencodehx.sync.SyncRouteRuntime.SyncRouteEvent;
import opencodehx.sync.WorkspaceSyncRemoteHttp;
import opencodehx.sync.WorkspaceSyncRuntime.WorkspaceSyncHttpTarget;

typedef WorkspaceRestoreProgress = {
	final workspaceID:String;
	final sessionID:String;
	final step:Int;
	final total:Int;
}

typedef WorkspaceRestoreResult = {
	final total:Int;
}

typedef WorkspaceRestoreInput = {
	final workspaceID:String;
	final sessionID:String;
	final directory:String;
	final events:Array<SyncRouteEvent>;
	final target:WorkspaceRestoreTarget;
	@:optional final batchSize:Int;
	@:optional final sessionUpdatedType:String;
	@:optional final emit:WorkspaceRestoreProgress->Void;
}

enum WorkspaceRestoreTarget {
	RestoreLocal(runtime:SyncRouteRuntime);
	RestoreRemote(remote:WorkspaceSyncRemoteHttp, target:WorkspaceSyncHttpTarget);
}

/**
	Focused model of upstream Workspace.sessionRestore replay behavior.

	The full upstream service also owns database queries, adaptor lifecycle, and
	AppRuntime/Instance context. This runtime intentionally starts after those
	boundaries: callers provide typed sync events and a resolved local or remote
	target, and the helper appends the workspace session-update event, replays in
	upstream-sized batches, and emits deterministic progress.
**/
class WorkspaceRestoreRuntime {
	public static inline final DEFAULT_BATCH_SIZE = 10;
	public static inline final SESSION_UPDATED_TYPE = "session.updated.1";

	@:async
	public static function sessionRestore(input:WorkspaceRestoreInput):Promise<WorkspaceRestoreResult> {
		final batchSize = input.batchSize == null || input.batchSize <= 0 ? DEFAULT_BATCH_SIZE : input.batchSize;
		final events = input.events.copy();
		events.push(sessionUpdatedEventAfter(input.sessionID, input.workspaceID, nextSeq(input.sessionID, input.events), input.sessionUpdatedType));
		final total = Std.int(Math.ceil(events.length / batchSize));
		emit(input, 0, total);
		var offset = 0;
		var step = 1;
		while (offset < events.length) {
			final batch = events.slice(offset, offset + batchSize);
			switch input.target {
				case RestoreLocal(runtime):
					runtime.replayAll(batch);
				case RestoreRemote(remote, target):
					await(remote.replay(target.url, target.headers, {directory: input.directory, events: batch}));
			}
			emit(input, step, total);
			offset += batchSize;
			step += 1;
		}
		return {total: total};
	}

	public static function sessionUpdatedEventAfter(sessionID:String, workspaceID:String, seq:Int, ?type:String):SyncRouteEvent {
		return {
			id: 'evt_workspace_restore_${sessionID}_${seq}',
			type: type == null ? SESSION_UPDATED_TYPE : type,
			seq: seq,
			aggregateID: sessionID,
			data: Unknown.fromBoundary(Json.value({
				sessionID: sessionID,
				info: {
					workspaceID: workspaceID,
				},
			})),
		};
	}

	static function nextSeq(sessionID:String, events:Array<SyncRouteEvent>):Int {
		var latest = -1;
		for (event in events) {
			if (event.aggregateID == sessionID && event.seq > latest)
				latest = event.seq;
		}
		return latest + 1;
	}

	static function emit(input:WorkspaceRestoreInput, step:Int, total:Int):Void {
		if (input.emit == null)
			return;
		input.emit({
			workspaceID: input.workspaceID,
			sessionID: input.sessionID,
			step: step,
			total: total,
		});
	}
}
