package opencodehx.smoke;

import genes.js.Async.await;
import haxe.DynamicAccess;
import js.lib.Promise;
import opencodehx.controlplane.WorkspaceAdaptors;
import opencodehx.controlplane.WorkspaceAdaptors.WorkspaceAdaptor;
import opencodehx.controlplane.WorkspaceAdaptors.WorkspaceInfo;
import opencodehx.controlplane.WorkspaceAdaptors.WorkspaceTarget;
import opencodehx.project.ProjectRuntime.ProjectID;

class ControlPlaneSmoke {
	@:async
	public static function run():Promise<Void> {
		WorkspaceAdaptors.reset();
		await(projectScopedAdaptors());
		await(latestAdaptorWins());
		WorkspaceAdaptors.reset();
	}

	@:async
	static function projectScopedAdaptors():Promise<Void> {
		final type = "demo-project-scoped";
		final one = ProjectID.make("project-one");
		final two = ProjectID.make("project-two");
		WorkspaceAdaptors.register(one, type, adaptor("/one"));
		WorkspaceAdaptors.register(two, type, adaptor("/two"));

		eq(localDirectory(await(WorkspaceAdaptors.get(one, type).target(info(one, type))), "project scoped one"), "/one", "project scoped one target");
		eq(localDirectory(await(WorkspaceAdaptors.get(two, type).target(info(two, type))), "project scoped two"), "/two", "project scoped two target");
		eq(WorkspaceAdaptors.list(one).length, 1, "project scoped list count");
		eq(WorkspaceAdaptors.list(one)[0].type, type, "project scoped list type");
	}

	@:async
	static function latestAdaptorWins():Promise<Void> {
		final type = "demo-latest-wins";
		final projectID = ProjectID.make("project-latest");
		WorkspaceAdaptors.register(projectID, type, adaptor("/one"));
		eq(localDirectory(await(WorkspaceAdaptors.get(projectID, type).target(info(projectID, type))), "latest first"), "/one", "latest first target");

		WorkspaceAdaptors.register(projectID, type, adaptor("/two"));
		eq(localDirectory(await(WorkspaceAdaptors.get(projectID, type).target(info(projectID, type))), "latest second"), "/two", "latest second target");
	}

	static function info(projectID:ProjectID, type:String):WorkspaceInfo {
		return {
			id: "workspace-test",
			type: type,
			name: "workspace-test",
			branch: null,
			directory: null,
			extra: null,
			projectID: projectID,
		};
	}

	static function adaptor(directory:String):WorkspaceAdaptor {
		return {
			name: directory,
			description: directory,
			configure: input -> Promise.resolve(input),
			create: createNoop,
			remove: _ -> resolvedVoid(),
			target: _ -> Promise.resolve(LocalTarget(directory)),
		};
	}

	static function createNoop(_info:WorkspaceInfo, _env:DynamicAccess<String>, ?_from:WorkspaceInfo):Promise<Void> {
		return resolvedVoid();
	}

	static function resolvedVoid():Promise<Void> {
		return new Promise<Void>((resolve, _) -> {
			final done:Void->Void = cast resolve;
			done();
		});
	}

	static function localDirectory(target:WorkspaceTarget, label:String):String {
		return switch target {
			case LocalTarget(directory):
				directory;
			case RemoteTarget(_, _):
				throw '${label}: expected local target';
		}
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
