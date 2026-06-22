package opencodehx.sync;

import haxe.ds.StringMap;
import opencodehx.sync.SyncRouteRuntime.SyncHistoryEvent;
import opencodehx.sync.SyncRouteRuntime.SyncRouteEvent;
import opencodehx.sync.SyncRouteRuntime.SyncRouteKnownSeq;

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

class WorkspaceSyncRuntime {
	final local:SyncRouteRuntime;
	final workspaces:Array<WorkspaceSyncWorkspace> = [];
	final syncing:StringMap<Bool> = new StringMap();

	public final statuses:Array<WorkspaceSyncStatusEvent> = [];
	public final failures:Array<WorkspaceSyncFailure> = [];

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
		final workspace = workspaceFor(workspaceID);
		if (workspace == null)
			throw 'Workspace not found: ${workspaceID}';
		startWorkspace(workspace);
	}

	public function sendLocalHistory(workspaceID:String, aggregateID:String):Null<String> {
		final workspace = workspaceFor(workspaceID);
		if (workspace == null)
			throw 'Workspace not found: ${workspaceID}';
		if (workspace.remote == null)
			return null;
		final events = local.events(aggregateID);
		if (events.length == 0)
			return null;
		return workspace.remote.replay(events);
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

	function setStatus(workspaceID:String, status:String):Void {
		if (statuses.length > 0) {
			final previous = statuses[statuses.length - 1];
			if (previous.workspaceID == workspaceID && previous.status == status)
				return;
		}
		statuses.push({workspaceID: workspaceID, status: status});
	}
}
