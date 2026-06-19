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
}

typedef InstanceBootstrap = InstanceContext->Bool;

typedef InstanceBootInput = {
	final directory:String;
	final worktree:String;
	final project:ProjectInfo;
	@:optional final init:InstanceBootstrap;
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

class InstanceRuntime {
	static var contexts:Map<String, InstanceContext> = new Map();
	static final history:Array<InstanceEvent> = [];
	static final listeners:Array<InstanceEventListener> = [];

	public static function reset():Void {
		contexts = new Map();
		history.resize(0);
		listeners.resize(0);
	}

	public static function fromDirectory(directory:String, ?init:InstanceBootstrap):Null<InstanceContext> {
		final discovery = ProjectRuntime.fromDirectory(directory);
		return boot({
			directory: directory,
			worktree: discovery.sandbox,
			project: discovery.project,
			init: init,
		});
	}

	public static function boot(input:InstanceBootInput):Null<InstanceContext> {
		final context:InstanceContext = {
			directory: canonical(input.directory),
			worktree: canonical(input.worktree),
			project: input.project,
		};
		final init = input.init;
		if (init != null && !init(context))
			return null;
		contexts.set(context.directory, context);
		return context;
	}

	public static function reload(input:InstanceBootInput):Null<InstanceContext> {
		dispose(input.directory);
		return boot(input);
	}

	public static function get(directory:String):Null<InstanceContext> {
		return contexts.get(canonical(directory));
	}

	public static function list():Array<InstanceContext> {
		final out:Array<InstanceContext> = [];
		for (context in contexts) {
			out.push(context);
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
		final context = contexts.get(key);
		if (context == null)
			return false;
		contexts.remove(key);
		publish({
			type: Disposed,
			directory: context.directory,
			project: context.project.id.toString(),
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

	static function canonical(path:String):String {
		final resolved = NodePath.normalize(NodePath.resolve(path, ""));
		final normalized = Fs.existsSync(resolved) ? NodePath.normalize(Fs.realpathSync(resolved)) : resolved;
		return NodeProcess.platform() == "win32" ? normalized.toLowerCase() : normalized;
	}
}
