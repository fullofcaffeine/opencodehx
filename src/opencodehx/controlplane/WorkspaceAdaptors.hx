package opencodehx.controlplane;

import genes.ts.Unknown;
import haxe.DynamicAccess;
import js.lib.Promise;
import opencodehx.project.ProjectRuntime.ProjectID;

typedef WorkspaceInfo = {
	final id:String;
	final type:String;
	final name:String;
	final branch:Null<String>;
	final directory:Null<String>;
	final extra:Null<Unknown>;
	final projectID:ProjectID;
}

enum WorkspaceTarget {
	LocalTarget(directory:String);
	RemoteTarget(url:String, ?headers:DynamicAccess<String>);
}

typedef WorkspaceAdaptor = {
	final name:String;
	final description:String;
	final configure:WorkspaceInfo->Promise<WorkspaceInfo>;
	final create:(WorkspaceInfo, DynamicAccess<String>, ?WorkspaceInfo) -> Promise<Void>;
	final remove:WorkspaceInfo->Promise<Void>;
	final target:WorkspaceInfo->Promise<WorkspaceTarget>;
}

typedef WorkspaceAdaptorEntry = {
	final type:String;
	final name:String;
	final description:String;
}

class WorkspaceAdaptors {
	static var custom:Map<String, Map<String, WorkspaceAdaptor>> = new Map();

	public static function reset():Void {
		custom = new Map();
	}

	public static function register(projectID:ProjectID, type:String, adaptor:WorkspaceAdaptor):Void {
		final key = projectID.toString();
		var adaptors = custom.get(key);
		if (adaptors == null) {
			adaptors = new Map();
			custom.set(key, adaptors);
		}
		adaptors.set(type, adaptor);
	}

	public static function get(projectID:ProjectID, type:String):WorkspaceAdaptor {
		final adaptors = custom.get(projectID.toString());
		if (adaptors != null) {
			final adaptor = adaptors.get(type);
			if (adaptor != null)
				return adaptor;
		}
		throw 'Unknown workspace adaptor: ${type}';
	}

	public static function list(projectID:ProjectID):Array<WorkspaceAdaptorEntry> {
		final out:Array<WorkspaceAdaptorEntry> = [];
		final adaptors = custom.get(projectID.toString());
		if (adaptors == null)
			return out;
		for (type in adaptors.keys()) {
			final adaptor = adaptors.get(type);
			out.push({
				type: type,
				name: adaptor.name,
				description: adaptor.description,
			});
		}
		out.sort((a, b) -> Reflect.compare(a.type, b.type));
		return out;
	}
}
