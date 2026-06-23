package opencodehx.project;

import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.externs.node.Fs;
import opencodehx.project.ProjectRuntime;
import opencodehx.project.ProjectRuntime.ProjectInfo;

/**
 * Minimal typed instance cache for directories that have completed bootstrap.
 *
 * Upstream OpenCode keeps one service context per project/worktree directory.
 * This seam preserves that lifecycle shape without porting the full service
 * graph yet: callers provide the discovered project and sandbox/worktree path,
 * optional bootstrap work runs first, and only successful contexts are cached.
 */
typedef InstanceContext = {
	final directory:String;
	final worktree:String;
	final project:ProjectInfo;
	final services:Array<InstanceServiceState>;
}

typedef InstanceBootstrap = InstanceContext->Bool;

enum abstract InstanceServiceID(String) to String {
	var Config = "config";
	var Plugin = "plugin";
	var Lsp = "lsp";
	var Share = "share";
	var Format = "format";
	var File = "file";
	var FileWatcher = "file-watcher";
	var Vcs = "vcs";
	var Snapshot = "snapshot";
	var Command = "command";
}

typedef InstanceServiceState = {
	final id:InstanceServiceID;
}

typedef InstanceServiceHandle = {
	final id:InstanceServiceID;
	@:optional final dispose:Void->Void;
}

typedef InstanceServiceFactory = InstanceContext->Null<InstanceServiceHandle>;

typedef InstanceBootInput = {
	final directory:String;
	final worktree:String;
	final project:ProjectInfo;
	@:optional final init:InstanceBootstrap;
	@:optional final services:Array<InstanceServiceFactory>;
}

enum abstract InstanceEventType(String) to String {
	var Disposed = "server.instance.disposed";
}

typedef InstanceEvent = {
	final type:InstanceEventType;
	final directory:String;
	final project:String;
}

typedef InstanceEventListener = InstanceEvent->Void;
typedef InstanceEventUnsubscribe = Void->Void;

private typedef InstanceEntry = {
	final context:InstanceContext;
	final disposers:Array<Void->Void>;
}

class InstanceRuntime {
	static var contexts:Map<String, InstanceEntry> = new Map();
	static final history:Array<InstanceEvent> = [];
	static final listeners:Array<InstanceEventListener> = [];

	public static function reset():Void {
		for (entry in contexts) {
			disposeServices(entry.disposers);
		}
		contexts = new Map();
		history.resize(0);
		listeners.resize(0);
	}

	public static function fromDirectory(directory:String, ?init:InstanceBootstrap, ?services:Array<InstanceServiceFactory>):Null<InstanceContext> {
		final discovery = ProjectRuntime.fromDirectory(directory);
		return boot({
			directory: directory,
			worktree: discovery.sandbox,
			project: discovery.project,
			init: init,
			services: services,
		});
	}

	public static function boot(input:InstanceBootInput):Null<InstanceContext> {
		final context:InstanceContext = {
			directory: canonical(input.directory),
			worktree: canonical(input.worktree),
			project: input.project,
			services: [],
		};
		final init = input.init;
		if (init != null && !init(context))
			return null;
		final disposers:Array<Void->Void> = [];
		if (!startServices(context, input.services, disposers))
			return null;
		contexts.set(context.directory, {context: context, disposers: disposers});
		return context;
	}

	public static function reload(input:InstanceBootInput):Null<InstanceContext> {
		dispose(input.directory);
		return boot(input);
	}

	public static function get(directory:String):Null<InstanceContext> {
		final entry = contexts.get(canonical(directory));
		return entry == null ? null : entry.context;
	}

	public static function list():Array<InstanceContext> {
		final out:Array<InstanceContext> = [];
		for (entry in contexts) {
			out.push(entry.context);
		}
		return out;
	}

	public static function events():Array<InstanceEvent> {
		return history.copy();
	}

	public static function subscribe(listener:InstanceEventListener):InstanceEventUnsubscribe {
		listeners.push(listener);
		var active = true;
		return () -> {
			if (!active)
				return;
			active = false;
			listeners.remove(listener);
		};
	}

	public static function dispose(directory:String):Bool {
		final key = canonical(directory);
		final entry = contexts.get(key);
		if (entry == null)
			return false;
		contexts.remove(key);
		disposeServices(entry.disposers);
		publish({
			type: Disposed,
			directory: entry.context.directory,
			project: entry.context.project.id.toString(),
		});
		return true;
	}

	public static function disposeAll():Void {
		final directories:Array<String> = [];
		for (directory in contexts.keys()) {
			directories.push(directory);
		}
		for (directory in directories) {
			dispose(directory);
		}
	}

	static function publish(event:InstanceEvent):Void {
		history.push(event);
		for (listener in listeners.copy()) {
			listener(event);
		}
	}

	static function startServices(context:InstanceContext, factories:Null<Array<InstanceServiceFactory>>, disposers:Array<Void->Void>):Bool {
		if (factories == null)
			return true;
		for (factory in factories) {
			final handle = factory(context);
			if (handle == null) {
				disposeServices(disposers);
				return false;
			}
			context.services.push({id: handle.id});
			final dispose = handle.dispose;
			if (dispose != null)
				disposers.push(dispose);
		}
		return true;
	}

	static function disposeServices(disposers:Array<Void->Void>):Void {
		var index = disposers.length;
		while (index > 0) {
			index--;
			disposers[index]();
		}
		disposers.resize(0);
	}

	static function canonical(path:String):String {
		final resolved = NodePath.normalize(NodePath.resolve(path, ""));
		final normalized = Fs.existsSync(resolved) ? NodePath.normalize(Fs.realpathSync(resolved)) : resolved;
		return NodeProcess.platform() == "win32" ? normalized.toLowerCase() : normalized;
	}
}
