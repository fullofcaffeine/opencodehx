package opencodehx.smoke;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.resource.Resources;

class ResourceSmoke {
	public static function run():Void {
		final prompt = Resources.text("prompt/example.txt");
		eq(prompt.indexOf("OpenCodeHX prompt fixture") != -1, true, "text resource");

		final sound = Resources.file("asset/pulse-a.wav");
		eq(Fs.existsSync(sound), true, "file resource exists");
		eq(NodePath.basename(sound), "pulse-a.wav", "file resource basename");

		final wasm = Resources.wasm("wasm/tree-sitter-fixture.wasm");
		eq(Fs.existsSync(wasm.path), true, "wasm resource exists");
		eq(wasm.byteLength > 4, true, "wasm byte length");
		eq(wasm.prefix[0], "w".code, "wasm prefix");
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
