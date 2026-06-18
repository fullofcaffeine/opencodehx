package opencodehx;

import genes.Genes;
import genes.ts.Imports;
import js.Syntax;
import opencodehx.cli.Cli;
import opencodehx.fixtures.DynamicFixture;
import opencodehx.fx.Task;
import opencodehx.host.node.NodePath;
import opencodehx.smoke.CliSmoke;
import opencodehx.smoke.ConfigSmoke;
import opencodehx.smoke.FileSmoke;
import opencodehx.smoke.MessageSmoke;
import opencodehx.smoke.ProviderSmoke;
import opencodehx.smoke.StorageSmoke;
import opencodehx.smoke.ToolSmoke;
import opencodehx.smoke.UtilSmoke;

typedef SmokeResource = {
	final name:String;
	final mode:String;
};

class Main {
	static function main():Void {
		final cli = Cli.run(argv());
		if (cli.handled) {
			write(cli.stdout, cli.stderr, cli.exitCode);
			return;
		}
		final smokePath = NodePath.normalize(NodePath.join("opencodehx", "smoke"));
		final smokeTask = Task.succeed(smokePath);
		final resource:SmokeResource = Imports.defaultImportWith("#opencodehx/smoke-resource", "json", "SmokeResourceJson");
		Syntax.code("void {0}", smokeTask.toEffect());
		Syntax.code("console.log({0})", '${BuildInfo.label()} ${smokePath}');
		Syntax.code("console.log({0})", '${resource.name}:${resource.mode}');
		UtilSmoke.run();
		Syntax.code("console.log({0})", "util-smoke:ok");
		CliSmoke.run();
		Syntax.code("console.log({0})", "cli-smoke:ok");
		ConfigSmoke.run();
		Syntax.code("console.log({0})", "config-smoke:ok");
		FileSmoke.run();
		Syntax.code("console.log({0})", "file-smoke:ok");
		MessageSmoke.run();
		Syntax.code("console.log({0})", "message-smoke:ok");
		StorageSmoke.run();
		Syntax.code("console.log({0})", "storage-smoke:ok");
		ToolSmoke.run();
		Syntax.code("console.log({0})", "tool-smoke:ok");
		ProviderSmoke.run();
		Syntax.code("console.log({0})", "provider-smoke:ok");
		Genes.dynamicImport(DynamicFixture -> DynamicFixture.label()).then(label -> {
			Syntax.code("console.log({0})", label);
			return null;
		});
	}

	static function argv():Array<String> {
		return Syntax.code("process.argv.slice(2)");
	}

	static function write(stdout:String, stderr:String, exitCode:Int):Void {
		if (stdout != "")
			Syntax.code("process.stdout.write({0})", stdout);
		if (stderr != "")
			Syntax.code("process.stderr.write({0})", stderr);
		if (exitCode != 0)
			Syntax.code("process.exitCode = {0}", exitCode);
	}
}
