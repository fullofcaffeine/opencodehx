package opencodehx.file;

import opencodehx.bus.EventBus;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Fs.FsWatcher;
import opencodehx.host.node.NodePath;

using StringTools;

enum abstract FileWatchEventType(String) to String {
	var FileUpdated = "file.updated";
}

enum abstract FileWatchChangeKind(String) to String {
	var Add = "add";
	var Change = "change";
	var Unlink = "unlink";
}

typedef FileUpdatedEvent = {
	final type:FileWatchEventType;
	final directory:Null<String>;
	final file:String;
	@:optional final event:FileWatchChangeKind;
}

typedef FileWatchCallback = FileUpdatedEvent->Void;

interface FileWatchHandle {
	function close():Void;
}

interface FileWatchBackend {
	function hasNativeBinding():Bool;
	function watch(directory:String, callback:FileWatchCallback):FileWatchHandle;
}

private class FsWatchHandle implements FileWatchHandle {
	final watcher:FsWatcher;

	public function new(watcher:FsWatcher) {
		this.watcher = watcher;
	}

	public function close():Void {
		watcher.close();
	}
}

class NodeFsWatchBackend implements FileWatchBackend {
	public function new() {}

	public function hasNativeBinding():Bool {
		return true;
	}

	public function watch(directory:String, callback:FileWatchCallback):FileWatchHandle {
		final watcher = Fs.watch(directory, {persistent: false}, (kind, name) -> {
			if (name == null || name == "")
				return;
			final file = NodePath.join(directory, name);
			callback({
				type: FileUpdated,
				directory: null,
				file: file,
				event: kind == "rename" && !Fs.existsSync(file) ? Unlink : Change,
			});
		});
		return new FsWatchHandle(watcher);
	}
}

class FileWatcherRuntime {
	final directory:String;
	final bus:EventBus<FileUpdatedEvent>;
	final backend:FileWatchBackend;
	final handles:Array<FileWatchHandle> = [];

	public function new(directory:String, bus:EventBus<FileUpdatedEvent>, ?backend:FileWatchBackend) {
		this.directory = NodePath.normalize(NodePath.resolve(directory, ""));
		this.bus = bus;
		this.backend = backend == null ? new NodeFsWatchBackend() : backend;
	}

	public function hasNativeBinding():Bool {
		return backend.hasNativeBinding();
	}

	public function init(?watchRoot:Bool = false, ?watchGit:Bool = true):Bool {
		if (!backend.hasNativeBinding())
			return false;
		if (watchRoot)
			subscribe(directory, shouldPublishRoot);
		if (watchGit) {
			final gitDir = NodePath.join(directory, ".git");
			if (Fs.existsSync(gitDir) && Fs.statSync(gitDir).isDirectory())
				subscribe(gitDir, shouldPublishGit);
		}
		return handles.length > 0;
	}

	public function dispose():Void {
		while (handles.length > 0) {
			final handle = handles.pop();
			if (handle != null)
				handle.close();
		}
	}

	function subscribe(path:String, filter:FileUpdatedEvent->Bool):Void {
		try {
			final handle = backend.watch(path, event -> {
				final normalized = normalizeEvent(path, event);
				if (filter(normalized))
					bus.publish(normalized);
			});
			handles.push(handle);
			// Dynamic is required here because native watcher setup can throw host
			// filesystem errors. init() contains the failure by skipping that path.
		} catch (error:Dynamic) {}
	}

	function normalizeEvent(watchDirectory:String, event:FileUpdatedEvent):FileUpdatedEvent {
		final raw = event.file;
		final absolute = NodePath.isAbsolute(raw) ? raw : NodePath.join(watchDirectory, raw);
		return {
			type: FileUpdated,
			directory: directory,
			file: NodePath.normalize(absolute),
			event: event.event,
		};
	}

	function shouldPublishRoot(event:FileUpdatedEvent):Bool {
		final rel = NodePath.relative(directory, event.file);
		return rel != "" && !rel.startsWith("..") && !NodePath.isAbsolute(rel) && rel != ".git" && !rel.startsWith(".git/") && !rel.startsWith(".git\\");
	}

	function shouldPublishGit(event:FileUpdatedEvent):Bool {
		return NodePath.basename(event.file) == "HEAD";
	}
}
