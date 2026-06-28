package opencodehx.effect;

import js.lib.Error;
import js.lib.Promise;

typedef RunnerOptions<T> = {
	@:optional final onInterrupt:Void->Promise<T>;
}

enum RunnerState {
	Idle;
	Running;
}

class RunnerCancelledError extends Error {
	public function new() {
		super("Runner was cancelled");
		this.name = "RunnerCancelledError";
	}
}

/**
	Small Promise-backed model of upstream Runner's shared-run contract.

	The real OpenCode runner owns Effect fibers and Scope integration. This
	runtime keeps only the stable app-facing semantics that can be tested without
	Effect: concurrent callers share the first run, later work is ignored while a
	run is active, failures reset the runner, and cancellation settles every
	waiting caller while stale Promise completions are discarded.
**/
class RunnerRuntime<T> {
	public var state(default, null):RunnerState;
	public var busy(default, null):Bool;

	final options:RunnerOptions<T>;
	var waiters:Array<RunnerWaiter<T>>;
	var runID:Int;

	public function new(?options:RunnerOptions<T>) {
		this.options = options == null ? {} : options;
		state = Idle;
		busy = false;
		waiters = [];
		runID = 0;
	}

	public function ensureRunning(work:Void->Promise<T>):Promise<T> {
		return new Promise<T>((resolve, reject) -> {
			waiters.push({resolve: resolve, reject: reject});
			if (state == Idle)
				start(work);
		});
	}

	public function cancel():Promise<Bool> {
		if (state == Idle)
			return resolvedVoid();

		final pending = drain();
		runID++;

		if (options.onInterrupt != null) {
			return options.onInterrupt().then(value -> {
				for (waiter in pending)
					waiter.resolve(value);
				return true;
			}).catchError(error -> {
				for (waiter in pending)
					waiter.reject(error);
				return true;
			});
		}

		final error = new RunnerCancelledError();
		for (waiter in pending)
			waiter.reject(error);
		return resolvedVoid();
	}

	function start(work:Void->Promise<T>):Void {
		state = Running;
		busy = true;
		final current = ++runID;
		work().then(value -> {
			if (current == runID && state == Running)
				completeSuccess(value);
			return null;
		}).catchError(error -> {
			if (current == runID && state == Running)
				completeFailure(error);
			return null;
		});
	}

	function completeSuccess(value:T):Void {
		final pending = drain();
		for (waiter in pending)
			waiter.resolve(value);
	}

	function completeFailure(error:Error):Void {
		final pending = drain();
		for (waiter in pending)
			waiter.reject(error);
	}

	function drain():Array<RunnerWaiter<T>> {
		final pending = waiters;
		waiters = [];
		state = Idle;
		busy = false;
		return pending;
	}

	static function resolvedVoid():Promise<Bool> {
		return Promise.resolve(true);
	}
}

private typedef RunnerWaiter<T> = {
	final resolve:T->Void;
	final reject:Error->Void;
}
