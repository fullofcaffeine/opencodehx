package opencodehx;

import genes.Genes;
import genes.ts.Imports;
import js.Syntax;
import opencodehx.cli.Cli;
import opencodehx.fixtures.DynamicFixture;
import opencodehx.fx.Task;
import opencodehx.host.node.NodePath;
import opencodehx.smoke.AiSdkProviderSmoke;
import opencodehx.smoke.CliSmoke;
import opencodehx.smoke.ConfigSmoke;
import opencodehx.smoke.CopilotChatCompletionSmoke;
import opencodehx.smoke.CopilotChatMessagesSmoke;
import opencodehx.smoke.CopilotChatRequestSmoke;
import opencodehx.smoke.CopilotChatSseDecoderSmoke;
import opencodehx.smoke.CopilotChatStreamAdapterSmoke;
import opencodehx.smoke.CopilotChatStreamSmoke;
import opencodehx.smoke.CopilotChatToolsSmoke;
import opencodehx.smoke.CopilotProviderFactorySmoke;
import opencodehx.smoke.FileSmoke;
import opencodehx.smoke.MessageSmoke;
import opencodehx.smoke.PermissionSmoke;
import opencodehx.smoke.ProjectRuntimeSmoke;
import opencodehx.smoke.ProviderSmoke;
import opencodehx.smoke.ProviderTransformSmoke;
import opencodehx.smoke.PtySmoke;
import opencodehx.smoke.ResourceSmoke;
import opencodehx.smoke.ServerSmoke;
import opencodehx.smoke.SessionProcessorSmoke;
import opencodehx.smoke.SkillSmoke;
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
		ResourceSmoke.run();
		Syntax.code("console.log({0})", "resource-smoke:ok");
		MessageSmoke.run();
		Syntax.code("console.log({0})", "message-smoke:ok");
		PermissionSmoke.run();
		Syntax.code("console.log({0})", "permission-smoke:ok");
		StorageSmoke.run();
		Syntax.code("console.log({0})", "storage-smoke:ok");
		ToolSmoke.run()
			.then(_ -> {
				Syntax.code("console.log({0})", "tool-smoke:ok");
				ProviderSmoke.run();
				return ProviderSmoke.runRemote();
			})
			.then(_ -> {
				Syntax.code("console.log({0})", "provider-smoke:ok");
				ProviderTransformSmoke.run();
				Syntax.code("console.log({0})", "provider-transform-smoke:ok");
				CopilotChatMessagesSmoke.run();
				Syntax.code("console.log({0})", "copilot-chat-messages-smoke:ok");
				CopilotChatCompletionSmoke.run();
				Syntax.code("console.log({0})", "copilot-chat-completion-smoke:ok");
				CopilotChatRequestSmoke.run();
				Syntax.code("console.log({0})", "copilot-chat-request-smoke:ok");
				CopilotProviderFactorySmoke.run();
				Syntax.code("console.log({0})", "copilot-provider-factory-smoke:ok");
				CopilotChatSseDecoderSmoke.run();
				Syntax.code("console.log({0})", "copilot-chat-sse-decoder-smoke:ok");
				return CopilotChatStreamAdapterSmoke.run();
			})
			.then(_ -> {
				Syntax.code("console.log({0})", "copilot-chat-stream-adapter-smoke:ok");
				CopilotChatStreamSmoke.run();
				Syntax.code("console.log({0})", "copilot-chat-stream-smoke:ok");
				CopilotChatToolsSmoke.run();
				Syntax.code("console.log({0})", "copilot-chat-tools-smoke:ok");
				return AiSdkProviderSmoke.run();
			})
			.then(_ -> {
				Syntax.code("console.log({0})", "ai-sdk-provider-smoke:ok");
				ProjectRuntimeSmoke.run();
				Syntax.code("console.log({0})", "project-runtime-smoke:ok");
				SkillSmoke.run();
				Syntax.code("console.log({0})", "skill-smoke:ok");
				SessionProcessorSmoke.run();
				Syntax.code("console.log({0})", "session-processor-smoke:ok");
				return PtySmoke.run();
			})
			.then(_ -> {
				Syntax.code("console.log({0})", "pty-smoke:ok");
				return SkillSmoke.runRemote();
			})
			.then(_ -> {
				Syntax.code("console.log({0})", "skill-remote-smoke:ok");
				return ConfigSmoke.runRemote();
			})
			.then(_ -> {
				Syntax.code("console.log({0})", "config-remote-smoke:ok");
				return ServerSmoke.run();
			})
			.then(_ -> {
				Syntax.code("console.log({0})", "server-smoke:ok");
				Genes.dynamicImport(DynamicFixture -> DynamicFixture.label()).then(label -> {
					Syntax.code("console.log({0})", label);
					return null;
				});
				return null;
			})
			.catchError(error -> {
				Syntax.code("console.error({0})", error);
				Syntax.code("process.exitCode = 1");
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
