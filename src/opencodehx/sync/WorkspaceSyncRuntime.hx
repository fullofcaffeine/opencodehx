package opencodehx.sync;

import genes.js.Async.await;
import haxe.DynamicAccess;
import haxe.ds.StringMap;
import js.html.AbortSignal;
import js.lib.Promise;
import js.lib.Uint8Array;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.sync.SyncRouteRuntime.SyncHistoryEvent;
import opencodehx.sync.SyncRouteRuntime.SyncRouteEvent;
import opencodehx.sync.SyncRouteRuntime.SyncRouteKnownSeq;
import opencodehx.sync.WorkspaceSyncSse.WorkspaceSyncSseEvent;
import opencodehx.sync.WorkspaceSyncSse.WorkspaceSyncGlobalEvent;

typedef WorkspaceSyncRemote = {
	final history:Array<SyncRouteKnownSeq>->Array<SyncHistoryEvent>;
	final replay:Array<SyncRouteEvent>->Null<String>;
}

typedef WorkspaceSyncWorkspace = {
	final id:String;
	final projectID:String;
	final directory:String;
	final activeSessionIDs:Array<String>;
	@:optional final remote:WorkspaceSyncRemote;
}

typedef WorkspaceSyncStatusEvent = {
	final workspaceID:String;
	final status:String;
}

typedef WorkspaceSyncFailure = {
	final workspaceID:String;
	final message:String;
}

typedef WorkspaceSyncFenceResult = {
	final synced:Bool;
	final message:Null<String>;
}

typedef WorkspaceSyncHttpTarget = {
	final url:String;
	final headers:Null<DynamicAccess<String>>;
}

typedef WorkspaceSyncLoopResult = {
	final attempts:Int;
	final applied:Int;
	final plannedDelays:Array<Int>;
}

class WorkspaceSyncRuntime {
	static inline final RECONNECT_DELAY_CAP_MS = 120000;
	static inline final RECONNECT_DELAY_BASE_MS = 1000;

	final local:SyncRouteRuntime;
	final workspaces:Array<WorkspaceSyncWorkspace> = [];
	final syncing:StringMap<Bool> = new StringMap();

	public final statuses:Array<WorkspaceSyncStatusEvent> = [];
	public final failures:Array<WorkspaceSyncFailure> = [];
	public final forwardedEvents:Array<WorkspaceSyncGlobalEvent> = [];

	public function new(local:SyncRouteRuntime) {
		this.local = local;
	}

	public function register(workspace:WorkspaceSyncWorkspace):Void {
		for (index in 0...workspaces.length) {
			if (workspaces[index].id == workspace.id) {
				workspaces[index] = workspace;
				return;
			}
		}
		workspaces.push(workspace);
	}

	public function start(projectID:String):Bool {
		var started = false;
		for (workspace in workspaces) {
			if (workspace.projectID != projectID || workspace.activeSessionIDs.length == 0)
				continue;
			started = true;
			startWorkspace(workspace);
		}
		return started;
	}

	public function isSyncing(workspaceID:String):Bool {
		return syncing.exists(workspaceID);
	}

	public function syncOnce(workspaceID:String):Void {
		startWorkspace(requireWorkspace(workspaceID));
	}

	public function sendLocalHistory(workspaceID:String, aggregateID:String):Null<String> {
		final workspace = requireWorkspace(workspaceID);
		if (workspace.remote == null)
			return null;
		final events = local.events(aggregateID);
		if (events.length == 0)
			return null;
		return workspace.remote.replay(events);
	}

	public function applyRemoteSse(workspaceID:String, text:String):Int {
		return applyRemoteEvents(requireWorkspace(workspaceID), WorkspaceSyncSse.parse(text));
	}

	@:async
	public function applyRemoteSseStream(workspaceID:String, body:WebReadableStream<Uint8Array>, ?signal:AbortSignal):Promise<Int> {
		final workspace = requireWorkspace(workspaceID);
		setStatus(workspaceID, "connected");
		final applied = applyRemoteEvents(workspace, @:await WorkspaceSyncSse.parseStream(body, signal));
		setStatus(workspaceID, "disconnected");
		return applied;
	}

	@:async
	public function runRemoteLoop(workspaceID:String, remote:WorkspaceSyncRemoteHttp, target:WorkspaceSyncHttpTarget, maxAttempts:Int,
			?signal:AbortSignal):Promise<WorkspaceSyncLoopResult> {
		final workspace = requireWorkspace(workspaceID);
		var attempt = 0;
		var applied = 0;
		var completed = 0;
		final plannedDelays:Array<Int> = [];
		while (completed < maxAttempts && !signalAborted(signal)) {
			setStatus(workspace.id, "connecting");
			try {
				final stream = @:await remote.connectSse(target.url, target.headers, signal);
				final history = @:await remote.syncHistory(target.url, target.headers, local.knownSeqs(workspace.activeSessionIDs), signal);
				applyHistoryEvents(history.events);
				setStatus(workspace.id, "connected");
				attempt = 0;
				applied += @:await applyRemoteSseStream(workspace.id, stream, signal);
			} catch (error:haxe.Exception) {
				setStatus(workspace.id, "error");
				failures.push({workspaceID: workspace.id, message: error.message});
			}
			completed += 1;
			if (!signalAborted(signal)) {
				plannedDelays.push(reconnectDelayMs(attempt));
				attempt += 1;
			}
		}
		return {
			attempts: completed,
			applied: applied,
			plannedDelays: plannedDelays,
		};
	}

	function applyRemoteEvents(workspace:WorkspaceSyncWorkspace, events:Array<WorkspaceSyncSseEvent>):Int {
		var applied = 0;
		for (event in events) {
			final global = event.global;
			if (global == null)
				continue;
			forwardedEvents.push({
				directory: global.directory == null ? workspace.directory : global.directory,
				project: global.project == null ? workspace.projectID : global.project,
				workspace: workspace.id,
				payload: global.payload,
			});
			if (global.payload.type != "sync" || global.payload.syncEvent == null)
				continue;
			try {
				local.replayOne(global.payload.syncEvent);
				applied += 1;
			} catch (error:haxe.Exception) {
				failures.push({workspaceID: workspace.id, message: 'failed to replay global event: ${error.message}'});
			}
		}
		if (applied > 0)
			setStatus(workspace.id, "connected");
		return applied;
	}

	function applyHistoryEvents(events:Array<SyncHistoryEvent>):Void {
		for (event in events) {
			local.replayOne({
				id: event.id,
				type: event.type,
				seq: event.seq,
				aggregateID: event.aggregate_id,
				data: event.data,
			});
		}
	}

	public function waitForSyncFence(workspaceID:String, state:Array<SyncRouteKnownSeq>):WorkspaceSyncFenceResult {
		if (isFenceSynced(state))
			return {synced: true, message: null};
		return {
			synced: false,
			message: 'Timed out waiting for sync fence: ${fenceStateJson(state)}',
		};
	}

	public function isFenceSynced(state:Array<SyncRouteKnownSeq>):Bool {
		if (state.length == 0)
			return true;
		for (item in state) {
			final current = local.knownSeqs([item.aggregateID])[0].seq;
			if (current < item.seq)
				return false;
		}
		return true;
	}

	public static function reconnectDelayMs(attempt:Int):Int {
		if (attempt <= 0)
			return RECONNECT_DELAY_BASE_MS;
		var delay = RECONNECT_DELAY_BASE_MS;
		for (_ in 0...attempt) {
			if (delay >= Std.int(RECONNECT_DELAY_CAP_MS / 2))
				return RECONNECT_DELAY_CAP_MS;
			delay *= 2;
		}
		return delay > RECONNECT_DELAY_CAP_MS ? RECONNECT_DELAY_CAP_MS : delay;
	}

	function startWorkspace(workspace:WorkspaceSyncWorkspace):Void {
		if (workspace.remote == null) {
			setStatus(workspace.id, workspace.directory == "" ? "error" : "connected");
			return;
		}
		if (!syncing.exists(workspace.id))
			setStatus(workspace.id, "disconnected");
		syncing.set(workspace.id, true);
		try {
			setStatus(workspace.id, "connecting");
			final known = local.knownSeqs(workspace.activeSessionIDs);
			final events = workspace.remote.history(known);
			for (event in events) {
				local.replayOne({
					id: event.id,
					type: event.type,
					seq: event.seq,
					aggregateID: event.aggregate_id,
					data: event.data,
				});
			}
			setStatus(workspace.id, "connected");
		} catch (error:haxe.Exception) {
			setStatus(workspace.id, "error");
			failures.push({workspaceID: workspace.id, message: error.message});
		}
	}

	function workspaceFor(workspaceID:String):Null<WorkspaceSyncWorkspace> {
		for (workspace in workspaces) {
			if (workspace.id == workspaceID)
				return workspace;
		}
		return null;
	}

	function requireWorkspace(workspaceID:String):WorkspaceSyncWorkspace {
		final workspace = workspaceFor(workspaceID);
		if (workspace == null)
			throw 'Workspace not found: ${workspaceID}';
		return workspace;
	}

	function setStatus(workspaceID:String, status:String):Void {
		if (statuses.length > 0) {
			final previous = statuses[statuses.length - 1];
			if (previous.workspaceID == workspaceID && previous.status == status)
				return;
		}
		statuses.push({workspaceID: workspaceID, status: status});
	}

	static function fenceStateJson(state:Array<SyncRouteKnownSeq>):String {
		final fields = [];
		for (item in state)
			fields.push('"${item.aggregateID}":${item.seq}');
		return "{" + fields.join(",") + "}";
	}

	static function signalAborted(signal:Null<AbortSignal>):Bool {
		return signal != null && signal.aborted;
	}
}
