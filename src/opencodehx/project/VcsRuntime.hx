package opencodehx.project;

import opencodehx.bus.EventBus;
import opencodehx.externs.node.Fs;
import opencodehx.file.FileWatcherRuntime.FileUpdatedEvent;
import opencodehx.file.FileWatcherRuntime.FileWatchEventType;
import opencodehx.git.Git;
import opencodehx.git.Git.GitChangeKind;
import opencodehx.git.Git.GitItem;
import opencodehx.git.Git.GitStat;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;

using StringTools;

enum abstract VcsDiffMode(String) to String {
	var WorkingTree = "git";
	var Branch = "branch";
}

enum abstract VcsEventType(String) to String {
	var BranchUpdated = "vcs.branch.updated";
}

typedef VcsFileDiff = {
	final file:String;
	final additions:Int;
	final deletions:Int;
	final status:GitChangeKind;
	@:optional final patch:String;
}

typedef VcsEvent = {
	final type:VcsEventType;
	final branch:Null<String>;
}

typedef VcsEventListener = VcsEvent->Void;
typedef VcsEventUnsubscribe = Void->Void;

class VcsRuntime {
	final directory:String;
	final history:Array<VcsEvent> = [];
	final listeners:Array<VcsEventListener> = [];
	final eventBus:Null<EventBus<VcsEvent>>;
	var fileUnsubscribe:Null<Void->Void>;
	var current:Null<String>;

	public function new(directory:String, ?eventBus:EventBus<VcsEvent>, ?fileBus:EventBus<FileUpdatedEvent>) {
		this.directory = canonical(directory);
		this.eventBus = eventBus;
		current = Git.branch(directory);
		final attached = fileBus;
		if (attached != null)
			fileUnsubscribe = attached.subscribe(handleFileEvent);
	}

	public function branch():Null<String> {
		return current;
	}

	public function defaultBranch():Null<String> {
		final base = Git.defaultBranch(directory);
		return base == null ? null : base.name;
	}

	public function diff(mode:VcsDiffMode):Array<VcsFileDiff> {
		return switch mode {
			case WorkingTree:
				track(Git.hasHead(directory) ? "HEAD" : null);
			case Branch:
				final base = Git.defaultBranch(directory);
				if (base == null || (current != null && current == base.name)) {
					[];
				} else {
					final ref = Git.mergeBase(directory, base.ref);
					ref == null ? [] : compare(ref);
				}
		}
	}

	public function refresh():Null<String> {
		final next = Git.branch(directory);
		if (next != current) {
			current = next;
			publish({type: BranchUpdated, branch: next});
		}
		return current;
	}

	public function events():Array<VcsEvent> {
		return history.copy();
	}

	public function subscribe(listener:VcsEventListener):VcsEventUnsubscribe {
		listeners.push(listener);
		var active = true;
		return () -> {
			if (!active)
				return;
			active = false;
			listeners.remove(listener);
		};
	}

	public function dispose():Void {
		final unsubscribe = fileUnsubscribe;
		if (unsubscribe == null)
			return;
		fileUnsubscribe = null;
		unsubscribe();
	}

	function publish(event:VcsEvent):Void {
		history.push(event);
		for (listener in listeners.copy()) {
			listener(event);
		}
		final target = eventBus;
		if (target != null)
			target.publish(event);
	}

	function handleFileEvent(event:FileUpdatedEvent):Void {
		if (event.type != FileUpdated)
			return;
		final eventDirectory = event.directory;
		if (eventDirectory != null && canonical(eventDirectory) != directory)
			return;
		if (!isHeadFile(event.file))
			return;
		refresh();
	}

	function track(ref:Null<String>):Array<VcsFileDiff> {
		if (ref == null)
			return files(null, Git.status(directory), []);
		return files(ref, Git.status(directory), Git.stats(directory, ref));
	}

	function compare(ref:String):Array<VcsFileDiff> {
		return files(ref, mergeItems(Git.diff(directory, ref), Git.status(directory).filter(item -> item.code == "??")), Git.stats(directory, ref));
	}

	function files(ref:Null<String>, items:Array<GitItem>, stats:Array<GitStat>):Array<VcsFileDiff> {
		final byFile = statsByFile(stats);
		final out:Array<VcsFileDiff> = [];
		for (item in uniqueItems(items)) {
			final stat = byFile.get(item.file);
			out.push({
				file: item.file,
				additions: stat == null ? fallbackAdditions(ref, item) : stat.additions,
				deletions: stat == null ? fallbackDeletions(ref, item) : stat.deletions,
				status: item.status,
			});
		}
		out.sort((a, b) -> Reflect.compare(a.file, b.file));
		return out;
	}

	function uniqueItems(items:Array<GitItem>):Array<GitItem> {
		final seen = new Map<String, Bool>();
		final out:Array<GitItem> = [];
		for (item in items) {
			if (seen.exists(item.file))
				continue;
			seen.set(item.file, true);
			out.push(item);
		}
		return out;
	}

	function mergeItems(first:Array<GitItem>, second:Array<GitItem>):Array<GitItem> {
		final out = first.copy();
		for (item in second)
			out.push(item);
		return out;
	}

	function statsByFile(stats:Array<GitStat>):Map<String, GitStat> {
		final out = new Map<String, GitStat>();
		for (stat in stats)
			out.set(stat.file, stat);
		return out;
	}

	function fallbackAdditions(ref:Null<String>, item:GitItem):Int {
		return item.status == Added ? lineCount(readWorkFile(item.file)) : 0;
	}

	function fallbackDeletions(ref:Null<String>, item:GitItem):Int {
		return item.status == Deleted && ref != null ? lineCount(Git.show(directory, ref, item.file)) : 0;
	}

	function readWorkFile(file:String):String {
		final path = NodePath.join(directory, file);
		if (!Fs.existsSync(path) || !Fs.statSync(path).isFile())
			return "";
		final text = Fs.readFileSync(path, "utf8");
		return text.indexOf(String.fromCharCode(0)) == -1 ? text : "";
	}

	static function lineCount(text:String):Int {
		if (text == "")
			return 0;
		final normalized = text.endsWith("\n") ? text.substr(0, text.length - 1) : text;
		return normalized == "" ? 0 : normalized.split("\n").length;
	}

	static function isHeadFile(file:String):Bool {
		return file == "HEAD" || file.endsWith("/HEAD") || file.endsWith("\\HEAD");
	}

	static function canonical(path:String):String {
		final resolved = NodePath.normalize(NodePath.resolve(path, ""));
		final normalized = Fs.existsSync(resolved) ? NodePath.normalize(Fs.realpathSync(resolved)) : resolved;
		return NodeProcess.platform() == "win32" ? normalized.toLowerCase() : normalized;
	}
}
