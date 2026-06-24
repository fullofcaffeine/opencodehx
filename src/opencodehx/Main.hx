package opencodehx;

import genes.Genes;
import genes.ts.Imports;
import opencodehx.externs.node.Console;
import opencodehx.externs.node.Process;
import opencodehx.cli.Cli;
import opencodehx.fixtures.DynamicFixture;
import opencodehx.fx.Task;
import opencodehx.host.node.NodePath;
import opencodehx.smoke.AiSdkProviderSmoke;
import opencodehx.smoke.BusSmoke;
import opencodehx.smoke.CliSmoke;
import opencodehx.smoke.ConfigSmoke;
import opencodehx.smoke.CopilotChatCompletionSmoke;
import opencodehx.smoke.CopilotChatHttpClientSmoke;
import opencodehx.smoke.CopilotChatLanguageModelSmoke;
import opencodehx.smoke.CopilotChatMessagesSmoke;
import opencodehx.smoke.CopilotChatRequestSmoke;
import opencodehx.smoke.CopilotChatSseDecoderSmoke;
import opencodehx.smoke.CopilotChatStreamAdapterSmoke;
import opencodehx.smoke.CopilotChatStreamSmoke;
import opencodehx.smoke.CopilotChatToolsSmoke;
import opencodehx.smoke.CopilotProviderFactorySmoke;
import opencodehx.smoke.CopilotResponsesLanguageModelSmoke;
import opencodehx.smoke.ControlPlaneSmoke;
import opencodehx.smoke.EffectSmoke;
import opencodehx.smoke.FileSmoke;
import opencodehx.smoke.FixtureSmoke;
import opencodehx.smoke.FormatterSmoke;
import opencodehx.smoke.LspSmoke;
import opencodehx.smoke.MessageSmoke;
import opencodehx.smoke.McpAcpSmoke;
import opencodehx.smoke.PermissionSmoke;
import opencodehx.smoke.PluginSmoke;
import opencodehx.smoke.ProjectRuntimeSmoke;
import opencodehx.smoke.ProviderSmoke;
import opencodehx.smoke.ProviderTransformSmoke;
import opencodehx.smoke.PtySmoke;
import opencodehx.smoke.ResourceSmoke;
import opencodehx.smoke.SdkCompatSmoke;
import opencodehx.smoke.ServerSmoke;
import opencodehx.smoke.SessionPersistenceSmoke;
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
		Cli.runAsync(argv()).then(cli -> {
			if (cli.handled) {
				write(cli.stdout, cli.stderr, cli.exitCode);
				return null;
			}
			runSmoke();
			return null;
		}).catchError(error -> {
			Console.error(error);
			Process.exitCode = 1;
			return null;
		});
	}

	static function runSmoke():Void {
		final smokePath = NodePath.normalize(NodePath.join("opencodehx", "smoke"));
		final smokeTask = Task.succeed(smokePath);
		final resource:SmokeResource = Imports.defaultImportWith("#opencodehx/smoke-resource", "json", "SmokeResourceJson");
		smokeTask.toEffect();
		log('${BuildInfo.label()} ${smokePath}');
		log('${resource.name}:${resource.mode}');
		UtilSmoke.run();
		log("util-smoke:ok");
		UtilSmoke.runAsync()
			.then(_ -> {
				log("util-async-smoke:ok");
				BusSmoke.run();
				log("bus-smoke:ok");
				EffectSmoke.run();
				log("effect-smoke:ok");
				FixtureSmoke.run();
				log("fixture-smoke:ok");
				CliSmoke.run();
				log("cli-smoke:ok");
				ConfigSmoke.run();
				log("config-smoke:ok");
				FileSmoke.run();
				log("file-smoke:ok");
				return FileSmoke.runAsync();
			})
			.then(_ -> {
				log("file-async-smoke:ok");
				ResourceSmoke.run();
				log("resource-smoke:ok");
				MessageSmoke.run();
				log("message-smoke:ok");
				PermissionSmoke.run();
				log("permission-smoke:ok");
				StorageSmoke.run();
				log("storage-smoke:ok");
				return ToolSmoke.run();
			})
			.then(_ -> {
				log("tool-smoke:ok");
				ProviderSmoke.run();
				return ProviderSmoke.runRemote();
			})
			.then(_ -> {
				log("provider-smoke:ok");
				ProviderTransformSmoke.run();
				log("provider-transform-smoke:ok");
				CopilotChatMessagesSmoke.run();
				log("copilot-chat-messages-smoke:ok");
				CopilotChatCompletionSmoke.run();
				log("copilot-chat-completion-smoke:ok");
				CopilotChatRequestSmoke.run();
				log("copilot-chat-request-smoke:ok");
				CopilotProviderFactorySmoke.run();
				log("copilot-provider-factory-smoke:ok");
				CopilotChatSseDecoderSmoke.run();
				log("copilot-chat-sse-decoder-smoke:ok");
				return CopilotChatStreamAdapterSmoke.run();
			})
			.then(_ -> {
				log("copilot-chat-stream-adapter-smoke:ok");
				CopilotChatStreamSmoke.run();
				log("copilot-chat-stream-smoke:ok");
				CopilotChatToolsSmoke.run();
				log("copilot-chat-tools-smoke:ok");
				return CopilotChatHttpClientSmoke.run();
			})
			.then(_ -> {
				log("copilot-chat-http-client-smoke:ok");
				return CopilotChatLanguageModelSmoke.run();
			})
			.then(_ -> {
				log("copilot-chat-language-model-smoke:ok");
				return CopilotResponsesLanguageModelSmoke.run();
			})
			.then(_ -> {
				log("copilot-responses-language-model-smoke:ok");
				return AiSdkProviderSmoke.run();
			})
			.then(_ -> {
				log("ai-sdk-provider-smoke:ok");
				return CliSmoke.runAsync();
			})
			.then(_ -> {
				log("cli-async-smoke:ok");
				ProjectRuntimeSmoke.run();
				log("project-runtime-smoke:ok");
				SkillSmoke.run();
				log("skill-smoke:ok");
				SessionPersistenceSmoke.run();
				log("session-persistence-smoke:ok");
				SessionProcessorSmoke.run();
				log("session-processor-smoke:ok");
				return SessionProcessorSmoke.runAsync();
			})
			.then(_ -> {
				log("session-processor-async-smoke:ok");
				return PtySmoke.run();
			})
			.then(_ -> {
				log("pty-smoke:ok");
				return SkillSmoke.runRemote();
			})
			.then(_ -> {
				log("skill-remote-smoke:ok");
				return ConfigSmoke.runRemote();
			})
			.then(_ -> {
				log("config-remote-smoke:ok");
				return FormatterSmoke.run();
			})
			.then(_ -> {
				log("formatter-smoke:ok");
				return SdkCompatSmoke.run();
			})
			.then(_ -> {
				log("sdk-compat-smoke:ok");
				McpAcpSmoke.run();
				log("mcp-acp-smoke:ok");
				LspSmoke.run();
				log("lsp-smoke:ok");
				PluginSmoke.run();
				log("plugin-smoke:ok");
				return ControlPlaneSmoke.run();
			})
			.then(_ -> {
				log("control-plane-smoke:ok");
				return ServerSmoke.run();
			})
			.then(_ -> {
				log("server-smoke:ok");
				Genes.dynamicImport(DynamicFixture -> DynamicFixture.label()).then(label -> {
					log(label);
					return null;
				});
				return null;
			})
			.catchError(error -> {
				Console.error(error);
				Process.exitCode = 1;
				return null;
			});
	}

	static function argv():Array<String> {
		return Process.argv.slice(2);
	}

	static function write(stdout:String, stderr:String, exitCode:Int):Void {
		if (stdout != "")
			Process.stdout.write(stdout);
		if (stderr != "")
			Process.stderr.write(stderr);
		if (exitCode != 0)
			Process.exitCode = exitCode;
	}

	static function log(value:String):Void {
		Console.log(value);
	}
}
