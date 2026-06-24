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
			readFiles(root);
			ignoreRules();
			listWithIgnore(root);
			listEdges(root);
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

	static function readFiles(root:String):Void {
		write(root, "read/test.txt", "  content with spaces  \n\n");
		eq(FileSystem.read(root, "read/test.txt").content, "content with spaces", "read trims text");
		write(root, "read/empty.txt", "");
		eq(FileSystem.read(root, "read/empty.txt").content, "", "read empty text");
		write(root, "read/multiline.txt", "line1\nline2\nline3");
		eq(FileSystem.read(root, "read/multiline.txt").content, "line1\nline2\nline3", "read multiline text");
		eq(FileSystem.read(root, "read/missing.txt").content, "", "read missing text");

		write(root, "read/test.ts", "export const value = 1");
		write(root, "read/test.mts", "export const value = 1");
		write(root, "read/test.sh", "#!/usr/bin/env bash\necho hello");
		write(root, "read/Dockerfile", "FROM alpine:3.20");
		eq(FileSystem.read(root, "read/test.ts").content, "export const value = 1", "read ts as text");
		eq(FileSystem.read(root, "read/test.mts").content, "export const value = 1", "read mts as text");
		eq(FileSystem.read(root, "read/test.sh").content, "#!/usr/bin/env bash\necho hello", "read sh as text");
		eq(FileSystem.read(root, "read/Dockerfile").content, "FROM alpine:3.20", "read Dockerfile as text");
		eq(FileSystem.read(root, "read/test.txt").encoding, null, "read text has no encoding");

		writeBytes(root, "read/image.png", [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
		final png = FileSystem.read(root, "read/image.png");
		eq(png.type, "text", "read png type");
		eq(png.encoding, "base64", "read png encoding");
		eq(png.mimeType, "image/png", "read png mime");
		eq(png.content, "iVBORw0KGgo=", "read png base64");

		writeBytes(root, "read/test.jpg", [0xff, 0xd8, 0xff, 0xe0]);
		final jpg = FileSystem.read(root, "read/test.jpg");
		eq(jpg.encoding, "base64", "read jpg encoding");
		eq(jpg.mimeType, "image/jpeg", "read jpg mime");

		writeBytes(root, "read/binary.so", [0x7f, 0x45, 0x4c, 0x46]);
		final binary = FileSystem.read(root, "read/binary.so");
		eq(binary.type, "binary", "read binary type");
		eq(binary.content, "", "read binary empty content");
		expectFailure(() -> FileSystem.read(root, "../outside.txt"), "read escaped via read");
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

	static function listEdges(root:String):Void {
		write(root, "sub/a.txt", "");
		write(root, "sub/b.txt", "");
		final sub = FileSystem.list(root, "sub");
		eq(sub.length, 2, "list subdirectory count");
		eq(StringTools.startsWith(sub[0].path, "sub/"), true, "list subdirectory relative path");
		expectFailure(() -> FileSystem.list(root, "../outside"), "list escaped");

		final plain = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-file-plain-"));
		try {
			write(plain, "file.txt", "hi");
			for (node in FileSystem.list(plain))
				eq(node.ignored, false, "list without ignore marks false");
			Fs.rmSync(plain, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(plain, {recursive: true, force: true});
			throw error;
		}
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

	static function writeBytes(root:String, relative:String, bytes:Array<Int>):Void {
		final path = NodePath.join(root, relative);
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, js.lib.Uint8Array.from(bytes));
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
