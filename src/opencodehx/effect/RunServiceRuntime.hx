package opencodehx.effect;

import js.lib.Promise;
import js.lib.Error;

enum RunServiceExit<T> {
	Succeeded(value:T);
	Failed(error:Error);
	Interrupted;
}

typedef RunServiceCallback<T> = RunServiceExit<T>->Void;
typedef RunServiceForkSettler<T> = RunServiceExit<T>->Void;

class RunServiceFork<T> {
	public final exit:Promise<RunServiceExit<T>>;

	var settled = false;
	var resolveExit:Null<RunServiceForkSettler<T>> = null;

	public function new(promise:Promise<RunServiceExit<T>>) {
		exit = new Promise<RunServiceExit<T>>((resolve, _) -> {
			resolveExit = resolve;
			promise.then(result -> {
				settle(result);
				return null;
			});
		});
	}

	public function interrupt():Void {
		settle(Interrupted);
	}

	function settle(result:RunServiceExit<T>):Void {
		if (settled)
			return;
		settled = true;
		final resolve = resolveExit;
		if (resolve != null)
			resolve(result);
	}
}

class RunServiceRuntime<TService> {
	final factory:Void->TService;
	final services:Array<TService> = [];

	public function new(factory:Void->TService) {
		this.factory = factory;
	}

	public static function make<TService>(factory:Void->TService):RunServiceRuntime<TService> {
		return new RunServiceRuntime(factory);
	}

	public function run<TResult>(fn:TService->TResult):TResult {
		return fn(service());
	}

	public function runPromise<TResult>(fn:TService->Promise<TResult>):Promise<TResult> {
		return fn(service());
	}

	public function runPromiseExit<TResult>(fn:TService->Promise<TResult>):Promise<RunServiceExit<TResult>> {
		try {
			return fn(service()).then(value -> {
				return Succeeded(value);
			}).catchError((error:Error) -> {
				return Failed(error);
			});
		} catch (error:Error) {
			return Promise.resolve(Failed(error));
		}
	}

	public function runCallback<TResult>(fn:TService->Promise<TResult>, callback:RunServiceCallback<TResult>):Void {
		runPromiseExit(fn).then(result -> {
			callback(result);
			return null;
		});
	}

	public function runFork<TResult>(fn:TService->Promise<TResult>):RunServiceFork<TResult> {
		return new RunServiceFork(runPromiseExit(fn));
	}

	function service():TService {
		if (services.length == 0)
			services.push(factory());
		return services[0];
	}
}
