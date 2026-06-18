package opencodehx;

import genes.Genes;
import genes.ts.Imports;
import js.Syntax;
import opencodehx.fixtures.DynamicFixture;
import opencodehx.fx.Task;
import opencodehx.host.node.NodePath;
import opencodehx.smoke.ConfigSmoke;
import opencodehx.smoke.MessageSmoke;
import opencodehx.smoke.UtilSmoke;

typedef SmokeResource = {
	final name:String;
	final mode:String;
};

class Main {
	static function main():Void {
		final smokePath = NodePath.normalize(NodePath.join("opencodehx", "smoke"));
		final smokeTask = Task.succeed(smokePath);
		final resource:SmokeResource = Imports.defaultImportWith("#opencodehx/smoke-resource", "json", "SmokeResourceJson");
		Syntax.code("void {0}", smokeTask.toEffect());
		Syntax.code("console.log({0})", '${BuildInfo.label()} ${smokePath}');
		Syntax.code("console.log({0})", '${resource.name}:${resource.mode}');
		UtilSmoke.run();
		Syntax.code("console.log({0})", "util-smoke:ok");
		ConfigSmoke.run();
		Syntax.code("console.log({0})", "config-smoke:ok");
		MessageSmoke.run();
		Syntax.code("console.log({0})", "message-smoke:ok");
		Genes.dynamicImport(DynamicFixture -> DynamicFixture.label()).then(label -> {
			Syntax.code("console.log({0})", label);
			return null;
		});
	}
}
