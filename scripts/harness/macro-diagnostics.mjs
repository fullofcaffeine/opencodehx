import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "../..");
const generatedRoot = path.join(root, "test", ".generated", "macro-diagnostics");
const fixturePath = path.join(generatedRoot, "BadTuiKeybindAction.hx");

rmSync(generatedRoot, { recursive: true, force: true });
mkdirSync(generatedRoot, { recursive: true });
writeFileSync(
	fixturePath,
	`import opencodehx.tui.TuiKeybind.TuiKeybindActions;

class BadTuiKeybindAction {
	static function main():Void {
		TuiKeybindActions.action("theme_lsit");
	}
}
`,
);

const result = spawnSync("haxe", ["-cp", "src", "-cp", generatedRoot, "--main", "BadTuiKeybindAction", "-js", path.join(generatedRoot, "bad.js")], {
	cwd: root,
	encoding: "utf8",
	env: process.env,
});

const output = `${result.stdout ?? ""}${result.stderr ?? ""}`;
if (result.status === 0) {
	console.error("[macro-diagnostics] Expected bad keybind action fixture to fail compilation.");
	process.exit(1);
}

if (!output.includes('Unknown TUI keybind action "theme_lsit". Known actions: leader, theme_list, session_new.')) {
	console.error("[macro-diagnostics] Bad keybind action fixture failed with an unexpected diagnostic:");
	console.error(output);
	process.exit(1);
}

console.log("macro-diagnostics:ok");
