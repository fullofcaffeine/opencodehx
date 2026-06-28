package opencodehx.effect;

import js.lib.Promise;

enum abstract RuntimeLoggerID(String) to String {
	final Default = "default";
	final Tracer = "tracer";
	final Effect = "effect";
}

typedef AppRuntimeLoggerContext = {
	final loggers:RuntimeLoggerSet;
	final directory:Null<String>;
}

typedef AppRuntimeLoggerSnapshot = {
	final defaultLogger:Bool;
	final tracerLogger:Bool;
	final effectLogger:Bool;
	final size:Int;
	final directory:Null<String>;
}

/**
	Immutable logger identity set used by `AppRuntimeLoggerRuntime`.

	Upstream stores logger instances in Effect's `Logger.CurrentLoggers`
	reference. This set keeps the stable identity-level behavior needed by
	parity smokes while avoiding a broad Effect dependency in OpenCodeHX's
	current runtime foundation.
**/
class RuntimeLoggerSet {
	final values:Array<RuntimeLoggerID>;

	public var size(get, never):Int;

	public function new(values:Array<RuntimeLoggerID>) {
		this.values = [];
		for (value in values) {
			if (!has(value))
				this.values.push(value);
		}
	}

	public static function observability():RuntimeLoggerSet {
		return new RuntimeLoggerSet([Effect]);
	}

	public function has(id:RuntimeLoggerID):Bool {
		for (value in values) {
			if (value == id)
				return true;
		}
		return false;
	}

	public function copy():RuntimeLoggerSet {
		return new RuntimeLoggerSet(values.copy());
	}

	function get_size():Int {
		return values.length;
	}
}

/**
	Small model of the upstream AppRuntime logger/context contract.

	The full OpenCode runtime installs `Observability.layer` into Effect's
	`ManagedRuntime` and uses Effect services plus AsyncLocalStorage-backed
	instance refs. This runtime keeps only the stable app-facing facts that can
	be proven without that service graph: Observability replaces the default
	logger with the OpenCode Effect logger, AppRuntime exposes the same logger
	set, and a bridge can carry the current instance directory into a later
	Promise callback.
**/
class AppRuntimeLoggerRuntime {
	final context:AppRuntimeLoggerContext;

	public function new(?directory:String, ?loggers:RuntimeLoggerSet) {
		context = {
			loggers: loggers == null ? RuntimeLoggerSet.observability() : loggers.copy(),
			directory: directory,
		};
	}

	public static function make(?directory:String):AppRuntimeLoggerRuntime {
		return new AppRuntimeLoggerRuntime(directory);
	}

	public static function bridgeFor(context:AppRuntimeLoggerContext):AppRuntimeLoggerBridge {
		return new AppRuntimeLoggerBridge(context);
	}

	public static function snapshot(context:AppRuntimeLoggerContext):AppRuntimeLoggerSnapshot {
		return {
			defaultLogger: context.loggers.has(Default),
			tracerLogger: context.loggers.has(Tracer),
			effectLogger: context.loggers.has(Effect),
			size: context.loggers.size,
			directory: context.directory,
		};
	}

	public function current():AppRuntimeLoggerSnapshot {
		return snapshot(capture());
	}

	public function run<TResult>(fn:AppRuntimeLoggerContext->TResult):TResult {
		return fn(capture());
	}

	public function runPromise<TResult>(fn:AppRuntimeLoggerContext->Promise<TResult>):Promise<TResult> {
		return fn(capture());
	}

	public function bridge():AppRuntimeLoggerBridge {
		return bridgeFor(capture());
	}

	function capture():AppRuntimeLoggerContext {
		return {
			loggers: context.loggers.copy(),
			directory: context.directory,
		};
	}
}

/**
	Captured async bridge for AppRuntime logger and instance context.

	It intentionally models only Promise re-entry. Effect fibers, scopes,
	runFork, and ALS-backed context propagation remain outside this parity slice.
**/
class AppRuntimeLoggerBridge {
	final captured:AppRuntimeLoggerContext;

	public function new(context:AppRuntimeLoggerContext) {
		captured = {
			loggers: context.loggers.copy(),
			directory: context.directory,
		};
	}

	public function promise<TResult>(fn:AppRuntimeLoggerContext->TResult):Promise<TResult> {
		return Promise.resolve(fn({
			loggers: captured.loggers.copy(),
			directory: captured.directory,
		}));
	}
}
