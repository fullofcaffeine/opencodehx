package opencodehx.sync;

import genes.js.Async.await;
import js.html.AbortSignal;
import js.lib.Promise;
import opencodehx.externs.web.AbortControllerWithReason;
import opencodehx.externs.web.WebStreams.WebTimerHandle;
import opencodehx.externs.web.WebStreams.WebTimers;
import opencodehx.sync.WorkspaceSyncRuntime.WorkspaceSyncHttpTarget;

typedef WorkspaceSyncTaskTimer = {
	final delayMs:Int;
	final cancel:Void->Void;
}

typedef WorkspaceSyncTaskScheduler = {
	final schedule:(delayMs:Int, callback:Void->Void) -> WorkspaceSyncTaskTimer;
}

typedef WorkspaceSyncTaskState = {
	final running:Bool;
	final scheduled:Bool;
	final aborted:Bool;
}

class WorkspaceSyncBackgroundTask {
	final runtime:WorkspaceSyncRuntime;
	final workspaceID:String;
	final remote:WorkspaceSyncRemoteHttp;
	final target:WorkspaceSyncHttpTarget;
	final scheduler:WorkspaceSyncTaskScheduler;
	final controller:AbortControllerWithReason;

	var timer:Null<WorkspaceSyncTaskTimer> = null;
	var running = false;

	public function new(runtime:WorkspaceSyncRuntime, workspaceID:String, remote:WorkspaceSyncRemoteHttp, target:WorkspaceSyncHttpTarget,
			?scheduler:WorkspaceSyncTaskScheduler) {
		this.runtime = runtime;
		this.workspaceID = workspaceID;
		this.remote = remote;
		this.target = target;
		this.scheduler = scheduler == null ? realScheduler() : scheduler;
		this.controller = new AbortControllerWithReason();
	}

	public function start():Bool {
		if (running)
			return false;
		running = true;
		schedule(0);
		return true;
	}

	public function stop(?reason:String):Void {
		running = false;
		if (timer != null) {
			timer.cancel();
			timer = null;
		}
		controller.abort(reason == null ? "workspace sync stopped" : reason);
	}

	public function state():WorkspaceSyncTaskState {
		return {
			running: running,
			scheduled: timer != null,
			aborted: controller.signal.aborted,
		};
	}

	function schedule(delayMs:Int):Void {
		if (!running || controller.signal.aborted)
			return;
		if (timer != null)
			timer.cancel();
		timer = scheduler.schedule(delayMs, () -> {
			timer = null;
			runTick();
		});
	}

	function runTick():Void {
		if (!running || controller.signal.aborted)
			return;
		runTickAsync().catchError(error -> {
			if (running && !controller.signal.aborted)
				schedule(WorkspaceSyncRuntime.reconnectDelayMs(0));
			return null;
		});
	}

	@:async
	function runTickAsync():Promise<Void> {
		final result = @:await runtime.runRemoteLoop(workspaceID, remote, target, 1, controller.signal);
		if (!running || controller.signal.aborted)
			return;
		final delay = result.plannedDelays.length == 0 ? WorkspaceSyncRuntime.reconnectDelayMs(0) : result.plannedDelays[0];
		schedule(delay);
	}

	public function signal():AbortSignal {
		return controller.signal;
	}

	static function realScheduler():WorkspaceSyncTaskScheduler {
		return {
			schedule: (delayMs, callback) -> {
				final handle:WebTimerHandle = WebTimers.setTimeout(callback, delayMs);
				return {
					delayMs: delayMs,
					cancel: () -> WebTimers.clearTimeout(handle),
				};
			},
		};
	}
}
