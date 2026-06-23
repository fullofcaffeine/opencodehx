import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");
const generatedRoot = path.join(root, "test", ".generated", "macro-diagnostics");

rmSync(generatedRoot, { recursive: true, force: true });
mkdirSync(generatedRoot, { recursive: true });

expectCompileFailure(
	"BadTuiKeybindAction",
	`import opencodehx.tui.TuiKeybind.TuiKeybindActions;

class BadTuiKeybindAction {
	static function main():Void {
		TuiKeybindActions.action("theme_lsit");
	}
}
`,
	'Unknown TUI keybind action "theme_lsit". Known actions: leader, theme_list, session_new.',
);

expectCompileFailure(
	"BadToolID",
	`import opencodehx.tool.ToolTypes.ToolIDs;

class BadToolID {
	static function main():Void {
		ToolIDs.known("grepp");
	}
}
`,
	'Unknown source-authored tool id "grepp". Known tool ids: apply_patch, bash, edit, glob, grep, invalid, lsp, read, write.',
);

expectCompileFailure(
	"BadProviderID",
	`import opencodehx.provider.ProviderTypes.ProviderIDs;

class BadProviderID {
	static function main():Void {
		ProviderIDs.known("openaai");
	}
}
`,
	'Unknown source-authored provider id "openaai". Known provider ids: amazon-bedrock, anthropic, cloudflare-ai-gateway, gitlab, github-copilot, openai, opencode.',
);

expectCompileFailure(
	"BadTuiProviderID",
	`import opencodehx.tui.TuiDialogReplay.TuiProviderIDs;

class BadTuiProviderID {
	static function main():Void {
		TuiProviderIDs.known("anthropik");
	}
}
`,
	'Unknown source-authored TUI provider id "anthropik". Known TUI provider ids: anthropic, openai, opencode.',
);

expectCompileFailure(
	"BadServerEventType",
	`import opencodehx.server.ServerProtocol.ServerEventTypes;

class BadServerEventType {
	static function main():Void {
		ServerEventTypes.known("session.cretaed");
	}
}
`,
	'Unknown source-authored server event type "session.cretaed". Known server event types: server.connected, server.heartbeat, session.created, session.selected.',
);

expectCompileFailure(
	"BadResourcePath",
	`import opencodehx.resource.Resources.ResourcePaths;

class BadResourcePath {
	static function main():Void {
		ResourcePaths.known("prompt/missing.txt");
	}
}
`,
	'Unknown source-authored resource path "prompt/missing.txt". Known resource paths: asset/pulse-a.wav, prompt/example.txt, smoke-resource.json, wasm/tree-sitter-bash.wasm, wasm/tree-sitter-fixture.wasm, wasm/tree-sitter-powershell.wasm, wasm/tree-sitter.wasm, worker/parser-worker.mjs, worker/tui-worker.mjs.',
);

function expectCompileFailure(name, source, expectedDiagnostic) {
	const fixturePath = path.join(generatedRoot, `${name}.hx`);
	writeFileSync(fixturePath, source);

	const result = spawnSync("haxe", ["-cp", "../genes/src", "-cp", "src", "-cp", generatedRoot, "--main", name, "-js", path.join(generatedRoot, `${name}.js`)], {
		cwd: root,
		encoding: "utf8",
		env: process.env,
	});

	const output = `${result.stdout ?? ""}${result.stderr ?? ""}`;
	if (result.status === 0) {
		console.error(`[macro-diagnostics] Expected ${name} fixture to fail compilation.`);
		process.exit(1);
	}

	if (!output.includes(expectedDiagnostic)) {
		console.error(`[macro-diagnostics] ${name} fixture failed with an unexpected diagnostic:`);
		console.error(output);
		process.exit(1);
	}
}

console.log("macro-diagnostics:ok");
