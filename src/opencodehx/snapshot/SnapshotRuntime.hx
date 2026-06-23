package opencodehx.snapshot;

import opencodehx.project.InstanceRuntime.InstanceContext;
import opencodehx.project.InstanceRuntime.InstanceServiceID;

class SnapshotRuntime {
	public static function track(context:InstanceContext):String {
		if (!hasSnapshotService(context))
			throw "Snapshot service is not attached to this instance";
		return 'snap_${hashFast(context.project.id.toString() + "\n" + context.worktree)}';
	}

	static function hasSnapshotService(context:InstanceContext):Bool {
		for (service in context.services) {
			if (service.id == InstanceServiceID.Snapshot)
				return true;
		}
		return false;
	}

	static function hashFast(value:String):String {
		final hash = (value.length * 2654435761.0) % 2147483647.0;
		return StringTools.hex(Std.int(hash), 8);
	}
}
