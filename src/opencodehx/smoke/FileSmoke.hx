package opencodehx.smoke;

import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.file.FileIgnore;
import opencodehx.file.FileSystem;
import opencodehx.host.node.NodePath;

class FileSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-file-"));
		try {
			fixture(root);
			ignoreRules();
			listWithIgnore(root);
			pathSafety(root);
			ripgrepFiles(root);
			ripgrepSearch(root);
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function fixture(root:String):Void {
		write(root, ".gitignore", "*.tmp\nignored-dir/\n");
		write(root, ".ignore", "local-only.txt\n");
		write(root, "src/main.ts", "export const hello = 'needle';\n");
		write(root, "src/other.ts", "export const other = 'haystack';\n");
		write(root, ".hidden/config", "needle hidden\n");
		write(root, "notes.tmp", "ignored temp\n");
		write(root, "local-only.txt", "ignored local\n");
		write(root, "ignored-dir/file.ts", "ignored dir\n");
		write(root, "build/out.js", "default ignored folder\n");
	}

	static function ignoreRules():Void {
		eq(FileIgnore.match("node_modules/pkg/index.js"), true, "node_modules ignored");
		eq(FileIgnore.match("src/app.log"), true, "log ignored");
		eq(FileIgnore.match("src/app.log", {whitelist: ["src/app.log"]}), false, "whitelist wins");
		eq(FileIgnore.match("src/app.ts", {extra: ["src/*.ts"]}), true, "extra glob");
	}

	static function listWithIgnore(root:String):Void {
		final nodes = FileSystem.list(root);
		eq(nodes[0].type, "directory", "directories first");
		final ignored = findNode(nodes, "ignored-dir");
		eq(ignored.ignored, true, "gitignore directory");
		final tmp = findNode(nodes, "notes.tmp");
		eq(tmp.ignored, true, "gitignore file");
		final local = findNode(nodes, "local-only.txt");
		eq(local.ignored, true, ".ignore file");
	}

	static function pathSafety(root:String):Void {
		eq(FileSystem.contains(root, NodePath.join(root, "src/main.ts")), true, "contained path");
		eq(FileSystem.contains(root, NodePath.join(root, "../outside.ts")), false, "escaped path");
		expectFailure(() -> FileSystem.readText(root, "../outside.ts"), "read escaped");
		eq(FileSystem.readText(root, "src/main.ts").indexOf("needle") != -1, true, "read text");
	}

	static function ripgrepFiles(root:String):Void {
		final visible = FileSystem.files(root, ["*.ts"], false);
		eq(visible.indexOf("src/main.ts") != -1, true, "rg files glob");
		eq(visible.indexOf(".hidden/config") == -1, true, "hidden filtered");

		final hidden = FileSystem.files(root, [".hidden/*"], true);
		eq(hidden.indexOf(".hidden/config") != -1, true, "hidden included");
	}

	static function ripgrepSearch(root:String):Void {
		final result = FileSystem.search(root, "needle", ["*.ts"], 5);
		eq(result.partial, false, "search not partial");
		eq(result.items.length, 1, "search match count");
		eq(result.items[0].path, "src/main.ts", "search path");
		eq(result.items[0].lineNumber, 1, "search line");
	}

	static function write(root:String, relative:String, content:String):Void {
		final path = NodePath.join(root, relative);
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, content);
	}

	static function findNode(nodes:Array<opencodehx.file.FileSystem.FileNode>, name:String):opencodehx.file.FileSystem.FileNode {
		for (node in nodes) {
			if (node.name == name)
				return node;
		}
		throw 'missing node ${name}';
	}

	static function expectFailure(run:() -> Void, label:String):Void {
		try {
			run();
		} catch (_:Dynamic) {
			return;
		}
		throw '${label}: expected failure';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
