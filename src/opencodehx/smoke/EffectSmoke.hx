package opencodehx.smoke;

import haxe.DynamicAccess;
import opencodehx.effect.InstanceStateRuntime;
import opencodehx.effect.ObservabilityResource;
import opencodehx.effect.RunServiceRuntime;
import opencodehx.effect.RuntimeMemo;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.project.InstanceRuntime;
import opencodehx.project.ProjectRuntime;

typedef SmokeSharedService = {
	final id:Int;
}

typedef SmokeRuntimeService = {
	final get:Void->Int;
}

typedef SmokeStateValue = {
	final directory:String;
	final n:Int;
}

class EffectSmoke {
	public static function run():Void {
		observabilityResource();
		runServiceMemoMap();
		instanceState();
	}

	static function observabilityResource():Void {
		final decoded = ObservabilityResource.resource({
			env: env({
				OTEL_RESOURCE_ATTRIBUTES: "service.namespace=anomalyco,team=platform%2Cobservability,label=hello%3Dworld,key%2Fname=value%20here",
				OPENCODE_CLIENT: "cli",
			}),
			processRole: "main",
			runID: "run-test",
			instanceID: "instance-test",
			installationChannel: "dev",
		});
		eq(decoded.serviceName, "opencode", "observability service name");
		eq(decoded.attributes.get("service.namespace"), "anomalyco", "observability namespace");
		eq(decoded.attributes.get("team"), "platform,observability", "observability comma decode");
		eq(decoded.attributes.get("label"), "hello=world", "observability equals decode");
		eq(decoded.attributes.get("key/name"), "value here", "observability slash and space decode");

		final invalid = ObservabilityResource.resource({
			env: env({OTEL_RESOURCE_ATTRIBUTES: "service.namespace=anomalyco,broken", OPENCODE_CLIENT: "desktop"}),
			processRole: "main",
			runID: "run-invalid",
			instanceID: "instance-invalid",
		});
		eq(invalid.attributes.exists("service.namespace"), false, "observability invalid entry drops env attributes");
		eq(invalid.attributes.exists("opencode.client"), true, "observability invalid keeps builtin attributes");

		final collision = ObservabilityResource.resource({
			env: env({
				OTEL_RESOURCE_ATTRIBUTES: "opencode.client=web,service.instance.id=override,service.namespace=anomalyco",
				OPENCODE_CLIENT: "cli",
			}),
			processRole: "main",
			runID: "run-collision",
			instanceID: "instance-collision",
		});
		eq(collision.attributes.get("opencode.client"), "cli", "observability builtin client wins");
		eq(collision.attributes.get("service.namespace"), "anomalyco", "observability env namespace kept");
		eq(collision.attributes.get("service.instance.id"), "instance-collision", "observability builtin instance wins");
	}

	static function runServiceMemoMap():Void {
		var initialized = 0;
		final shared = new RuntimeMemo<SmokeSharedService>();
		final sharedLayer = () -> shared.get(() -> {
			initialized += 1;
			return {id: initialized};
		});

		final one:RunServiceRuntime<SmokeRuntimeService> = RunServiceRuntime.make(() -> {
			final svc = sharedLayer();
			final get = () -> svc.id;
			return {get: get};
		});
		final two:RunServiceRuntime<SmokeRuntimeService> = RunServiceRuntime.make(() -> {
			final svc = sharedLayer();
			final get = () -> svc.id;
			return {get: get};
		});

		eq(one.run(svc -> svc.get()), 1, "run-service first runtime shared id");
		eq(two.run(svc -> svc.get()), 1, "run-service second runtime shared id");
		eq(initialized, 1, "run-service dependent layer initialized once");
	}

	static function instanceState():Void {
		ProjectRuntime.reset();
		InstanceRuntime.reset();
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-instance-state-"));
		try {
			final one = directory(root, "one");
			final two = directory(root, "two");
			final projectOne = ProjectRuntime.fromDirectory(one).project;
			final projectTwo = ProjectRuntime.fromDirectory(two).project;
			var initialized = 0;
			final disposed:Array<String> = [];
			final state = new InstanceStateRuntime<SmokeStateValue>(context -> {
				initialized += 1;
				return {directory: context.directory, n: initialized};
			}, value -> disposed.push(value.directory));

			final contextOne = requireContext(InstanceRuntime.boot({directory: one, worktree: one, project: projectOne}), "instance state one boot");
			final a = state.get(contextOne);
			final b = state.get(contextOne);
			eq(a == b, true, "instance-state caches values per directory");
			eq(initialized, 1, "instance-state initializes cached directory once");

			final contextTwo = requireContext(InstanceRuntime.boot({directory: two, worktree: two, project: projectTwo}), "instance state two boot");
			final c = state.get(contextTwo);
			eq(a == c, false, "instance-state isolates directories");
			eq(initialized, 2, "instance-state initializes isolated directory");

			final reloaded = requireContext(InstanceRuntime.reload({directory: one, worktree: one, project: projectOne}), "instance state reload");
			final d = state.get(reloaded);
			eq(a == d, false, "instance-state invalidates on reload");
			eq(disposed.indexOf(a.directory) != -1, true, "instance-state disposes reloaded value");

			InstanceRuntime.disposeAll();
			eq(disposed.indexOf(c.directory) != -1, true, "instance-state disposes isolated value on disposeAll");
			eq(disposed.indexOf(d.directory) != -1, true, "instance-state disposes reloaded value on disposeAll");
			state.dispose();
		} catch (error:Dynamic) {
			InstanceRuntime.reset();
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
		Fs.rmSync(root, {recursive: true, force: true});
	}

	static function env(values:Dynamic<String>):DynamicAccess<String> {
		final out = new DynamicAccess<String>();
		for (field in Reflect.fields(values)) {
			out.set(field, Std.string(Reflect.field(values, field)));
		}
		return out;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}

	static function directory(root:String, name:String):String {
		final path = NodePath.join(root, name);
		Fs.mkdirSync(path, {recursive: true});
		return path;
	}

	static function requireContext<T>(context:Null<T>, label:String):T {
		if (context == null)
			throw '${label}: expected context';
		return context;
	}
}
