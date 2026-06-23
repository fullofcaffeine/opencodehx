package opencodehx.smoke;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.resource.Resources;
import opencodehx.resource.Resources.ResourcePaths;
import opencodehx.resource.Resources.ResourceManifestEntry;
import opencodehx.resource.Resources.ResourceKind;

class ResourceSmoke {
	public static function run():Void {
		final prompt = Resources.text(ResourcePaths.known("prompt/example.txt"));
		eq(prompt.indexOf("OpenCodeHX prompt fixture") != -1, true, "text resource");
		eq(requireEntry(ResourcePaths.known("prompt/example.txt")).kind, ResourceKind.Text, "prompt manifest kind");

		final sound = Resources.file(ResourcePaths.known("asset/pulse-a.wav"));
		eq(Fs.existsSync(sound), true, "file resource exists");
		eq(NodePath.basename(sound), "pulse-a.wav", "file resource basename");
		eq(requireEntry(ResourcePaths.known("asset/pulse-a.wav")).kind, ResourceKind.File, "file manifest kind");

		final wasm = Resources.wasm(ResourcePaths.known("wasm/tree-sitter-fixture.wasm"));
		eq(Fs.existsSync(wasm.path), true, "wasm resource exists");
		eq(wasm.byteLength > 4, true, "wasm byte length");
		eq(wasm.prefix[0], "w".code, "wasm prefix");
		eq(requireEntry(ResourcePaths.known("wasm/tree-sitter-fixture.wasm")).kind, ResourceKind.Wasm, "fixture wasm manifest kind");
		eq(requireEntry(ResourcePaths.known("wasm/tree-sitter.wasm")).kind, ResourceKind.Wasm, "npm wasm manifest kind");

		final manifest = Resources.manifest();
		eq(manifest.version, 1, "manifest version");
		eq(manifest.generatedBy, "scripts/build/copy-resources.mjs", "manifest generator");
		eq(requireEntry(ResourcePaths.known("smoke-resource.json")).kind, ResourceKind.JsonResource, "json manifest kind");

		final parserWorker = Resources.worker(ResourcePaths.known("worker/parser-worker.mjs"));
		final tuiWorker = Resources.worker(ResourcePaths.known("worker/tui-worker.mjs"));
		eq(Fs.existsSync(parserWorker), true, "parser worker exists");
		eq(Fs.existsSync(tuiWorker), true, "tui worker exists");
		eq(NodePath.basename(parserWorker), "parser-worker.mjs", "parser worker basename");
		eq(Resources.text(ResourcePaths.known("worker/tui-worker.mjs")).indexOf("OpenCodeHX TUI worker fixture") != -1, true, "tui worker text");
		eq(requireEntry(ResourcePaths.known("worker/parser-worker.mjs")).kind, ResourceKind.Worker, "parser worker manifest kind");
		eq(requireEntry(ResourcePaths.known("worker/tui-worker.mjs")).kind, ResourceKind.Worker, "tui worker manifest kind");
	}

	static function requireEntry(path:String):ResourceManifestEntry {
		final entry = Resources.manifestEntry(path);
		if (entry == null)
			throw 'missing manifest entry ${path}';
		eq(entry.bytes > 0, true, '${path} manifest bytes');
		eq(entry.sha256.length, 64, '${path} manifest sha');
		return entry;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
