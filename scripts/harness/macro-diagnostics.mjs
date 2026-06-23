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

function expectCompileFailure(name, source, expectedDiagnostic) {
	const fixturePath = path.join(generatedRoot, `${name}.hx`);
	writeFileSync(fixturePath, source);

	const result = spawnSync("haxe", ["-cp", "src", "-cp", generatedRoot, "--main", name, "-js", path.join(generatedRoot, `${name}.js`)], {
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
