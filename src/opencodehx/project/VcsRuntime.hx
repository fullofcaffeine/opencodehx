package opencodehx.project;

import opencodehx.git.Git;

enum abstract VcsEventType(String) to String {
	var BranchUpdated = "vcs.branch.updated";
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
	var current:Null<String>;

	public function new(directory:String) {
		this.directory = directory;
		current = Git.branch(directory);
	}

	public function branch():Null<String> {
		return current;
	}

	public function defaultBranch():Null<String> {
		final base = Git.defaultBranch(directory);
		return base == null ? null : base.name;
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

	function publish(event:VcsEvent):Void {
		history.push(event);
		for (listener in listeners.copy()) {
			listener(event);
		}
	}
}
