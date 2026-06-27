package opencodehx.smoke;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import js.lib.Promise;
import opencodehx.controlplane.WorkspaceAdaptors;
import opencodehx.controlplane.WorkspaceAdaptors.WorkspaceAdaptor;
import opencodehx.controlplane.WorkspaceAdaptors.WorkspaceEnv;
import opencodehx.controlplane.WorkspaceAdaptors.WorkspaceInfo;
import opencodehx.controlplane.WorkspaceAdaptors.WorkspaceTarget;
import opencodehx.plugin.PluginWorkspaceRuntime;
import opencodehx.project.ProjectRuntime.ProjectID;

class ControlPlaneSmoke {
	@:async
	public static function run():Promise<Void> {
		WorkspaceAdaptors.reset();
		await(projectScopedAdaptors());
		await(latestAdaptorWins());
		await(pluginWorkspaceRegistration());
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

	@:async
	static function pluginWorkspaceRegistration():Promise<Void> {
		final type = "plug-workspace";
		final projectID = ProjectID.make("project-plugin-workspace");
		final space = "/tmp/opencodehx-plugin-workspace";
		final extra = Unknown.fromBoundary({key: "value"});
		final created:Array<WorkspaceInfo> = [];
		final registry = PluginWorkspaceRuntime.registry(projectID);

		registry.register(type, {
			name: "plug",
			description: "plugin workspace adaptor",
			configure: input -> Promise.resolve({
				id: input.id,
				type: input.type,
				name: "plug",
				branch: "plug/main",
				directory: space,
				extra: input.extra,
				projectID: input.projectID,
			}),
			create: (input, _env, ?_from) -> {
				created.push(input);
				return resolvedVoid();
			},
			remove: _ -> resolvedVoid(),
			target: input -> Promise.resolve(LocalTarget(requireDirectory(input.directory, "plugin workspace target"))),
		});

		final registered = WorkspaceAdaptors.get(projectID, type);
		final configured = await(registered.configure({
			id: "plugin-workspace",
			type: type,
			name: "pending",
			branch: null,
			directory: null,
			extra: extra,
			projectID: projectID,
		}));
		await(registered.create(configured, WorkspaceAdaptors.emptyEnv()));

		eq(configured.type, type, "plugin workspace type");
		eq(configured.name, "plug", "plugin workspace configured name");
		eq(configured.branch, "plug/main", "plugin workspace configured branch");
		eq(configured.directory, space, "plugin workspace configured directory");
		eq(extraString(configured.extra, "key", "plugin workspace configured extra"), "value", "plugin workspace configured extra value");
		eq(created.length, 1, "plugin workspace create call count");
		eq(created[0].directory, space, "plugin workspace create directory");
		eq(extraString(created[0].extra, "key", "plugin workspace create extra"), "value", "plugin workspace create extra value");
		eq(localDirectory(await(registered.target(configured)), "plugin workspace target"), space, "plugin workspace local target");
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

	static function createNoop(_info:WorkspaceInfo, _env:WorkspaceEnv, ?_from:WorkspaceInfo):Promise<Void> {
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

	static function requireDirectory(directory:Null<String>, label:String):String {
		if (directory == null)
			throw '${label}: expected directory';
		return directory;
	}

	static function extraString(extra:Null<Unknown>, field:String, label:String):String {
		if (extra == null)
			throw '${label}: expected extra';
		final record = UnknownNarrow.record(extra);
		if (record == null)
			throw '${label}: expected record extra';
		final value = UnknownNarrow.string(record.get(field));
		if (value == null)
			throw '${label}: expected string field ${field}';
		return value;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
