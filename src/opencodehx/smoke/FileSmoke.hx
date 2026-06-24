package opencodehx.smoke;

import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.file.AppFileSystem;
import opencodehx.file.AppFileSystem.AppFileContent;
import opencodehx.file.FileIgnore;
import opencodehx.file.FileSystem;
import opencodehx.host.node.NodePath;

class FileSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-file-"));
		try {
			fixture(root);
			appFileSystem(root);
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
		eq(FileIgnore.match("node_modules/index.js"), true, "node_modules file ignored");
		eq(FileIgnore.match("node_modules"), true, "node_modules bare ignored");
		eq(FileIgnore.match("node_modules/"), true, "node_modules slash ignored");
		eq(FileIgnore.match("node_modules/bar"), true, "node_modules child ignored");
		eq(FileIgnore.match("node_modules/bar/"), true, "node_modules child slash ignored");
		eq(FileIgnore.match("node_modules/pkg/index.js"), true, "node_modules ignored");
		eq(FileIgnore.match("src/app.log"), true, "log ignored");
		eq(FileIgnore.match("src/app.log", {whitelist: ["src/app.log"]}), false, "whitelist wins");
		eq(FileIgnore.match("src/app.ts", {extra: ["src/*.ts"]}), true, "extra glob");
	}

	static function appFileSystem(root:String):Void {
		final tmp = NodePath.join(root, "appfs");
		AppFileSystem.ensureDir(tmp);
		eq(AppFileSystem.isDir(tmp), true, "appfs isDir directory");
		eq(AppFileSystem.isDir(NodePath.join(tmp, "missing")), false, "appfs isDir missing");
		final file = NodePath.join(tmp, "test.txt");
		AppFileSystem.writeFileString(file, "hello");
		eq(AppFileSystem.isFile(file), true, "appfs isFile file");
		eq(AppFileSystem.isFile(tmp), false, "appfs isFile directory");

		final jsonFile = NodePath.join(tmp, "data.json");
		AppFileSystem.writeJson(jsonFile, {name: "test", count: 42});
		final json:Dynamic = AppFileSystem.readJson(jsonFile);
		eq(Reflect.field(json, "name"), "test", "appfs json name");
		eq(Reflect.field(json, "count"), 42, "appfs json count");

		final nested = NodePath.join(NodePath.join(NodePath.join(tmp, "a"), "b"), "c");
		AppFileSystem.ensureDir(nested);
		AppFileSystem.ensureDir(nested);
		eq(AppFileSystem.isDir(nested), true, "appfs ensureDir nested idempotent");
		final deepFile = NodePath.join(NodePath.join(NodePath.join(tmp, "deep"), "nested"), "file.txt");
		AppFileSystem.writeWithDirs(deepFile, Text("hello"));
		eq(AppFileSystem.readFileString(deepFile), "hello", "appfs writeWithDirs string");
		final directFile = NodePath.join(tmp, "direct.txt");
		AppFileSystem.writeWithDirs(directFile, Text("world"));
		eq(AppFileSystem.readFileString(directFile), "world", "appfs writeWithDirs direct");
		final binaryFile = NodePath.join(tmp, "binary.bin");
		AppFileSystem.writeWithDirs(binaryFile, Bytes(js.lib.Uint8Array.from([0x00, 0x01, 0x02, 0x03])));
		final binary = AppFileSystem.readFile(binaryFile).subarray(0);
		eq(binary.length, 4, "appfs binary length");
		eq(binary[0], 0, "appfs binary byte 0");
		eq(binary[3], 3, "appfs binary byte 3");

		final targetFile = NodePath.join(tmp, "target.txt");
		AppFileSystem.writeFileString(targetFile, "found");
		eq(AppFileSystem.findUp("target.txt", tmp).join("|"), targetFile, "appfs findUp start");
		final marker = NodePath.join(tmp, "marker");
		AppFileSystem.writeFileString(marker, "root");
		final child = NodePath.join(NodePath.join(tmp, "walk"), "child");
		AppFileSystem.ensureDir(child);
		eq(AppFileSystem.findUp("marker", child, tmp).join("|"), marker, "appfs findUp parent");
		eq(AppFileSystem.findUp("nonexistent", tmp, tmp).length, 0, "appfs findUp missing");
		AppFileSystem.writeFileString(NodePath.join(tmp, "a.txt"), "a");
		AppFileSystem.writeFileString(NodePath.join(tmp, "b.txt"), "b");
		AppFileSystem.writeFileString(NodePath.join(child, "a.txt"), "a-child");
		final up = AppFileSystem.up({targets: ["a.txt", "b.txt"], start: child, stop: tmp});
		eq(up.indexOf(NodePath.join(child, "a.txt")) != -1, true, "appfs up child target");
		eq(up.indexOf(NodePath.join(tmp, "a.txt")) != -1, true, "appfs up root target a");
		eq(up.indexOf(NodePath.join(tmp, "b.txt")) != -1, true, "appfs up root target b");

		AppFileSystem.writeFileString(NodePath.join(tmp, "one.ts"), "one");
		AppFileSystem.writeFileString(NodePath.join(tmp, "two.ts"), "two");
		AppFileSystem.writeFileString(NodePath.join(tmp, "three.json"), "three");
		eq(AppFileSystem.glob("*.ts", {cwd: tmp}).join(","), "one.ts,two.ts", "appfs glob relative");
		eq(AppFileSystem.glob("*.txt", {cwd: tmp, absolute: true}).indexOf(NodePath.join(tmp, "a.txt")) != -1, true, "appfs glob absolute");
		eq(AppFileSystem.globMatch("*.ts", "foo.ts"), true, "appfs globMatch true");
		eq(AppFileSystem.globMatch("*.ts", "foo.json"), false, "appfs globMatch false");
		eq(AppFileSystem.globMatch("src/**", "src/a/b.ts"), true, "appfs globMatch nested");
		AppFileSystem.writeFileString(NodePath.join(tmp, "root.md"), "root");
		AppFileSystem.writeFileString(NodePath.join(child, "leaf.md"), "leaf");
		final globUp = AppFileSystem.globUp("*.md", child, tmp);
		eq(globUp.indexOf(NodePath.join(child, "leaf.md")) != -1, true, "appfs globUp child");
		eq(globUp.indexOf(NodePath.join(tmp, "root.md")) != -1, true, "appfs globUp root");

		final existsFile = NodePath.join(tmp, "exists.txt");
		AppFileSystem.writeFileString(existsFile, "yes");
		eq(AppFileSystem.exists(existsFile), true, "appfs exists true");
		eq(AppFileSystem.exists(existsFile + ".nope"), false, "appfs exists false");
		final removeFile = NodePath.join(tmp, "delete-me.txt");
		AppFileSystem.writeFileString(removeFile, "bye");
		AppFileSystem.remove(removeFile);
		eq(AppFileSystem.exists(removeFile), false, "appfs remove");
		eq(AppFileSystem.mimeType("file.json"), "application/json", "appfs mime json");
		eq(AppFileSystem.mimeType("image.png"), "image/png", "appfs mime png");
		eq(AppFileSystem.mimeType("unknown.qzx"), "application/octet-stream", "appfs mime unknown");
		eq(AppFileSystem.contains("/a/b", "/a/b/c"), true, "appfs contains true");
		eq(AppFileSystem.contains("/a/b", "/a/c"), false, "appfs contains false");
		eq(AppFileSystem.overlaps("/a/b", "/a/b/c"), true, "appfs overlaps child");
		eq(AppFileSystem.overlaps("/a/b/c", "/a/b"), true, "appfs overlaps parent");
		eq(AppFileSystem.overlaps("/a", "/b"), false, "appfs overlaps false");
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
		final projectRoot = NodePath.join(root, "project");
		write(projectRoot, "valid.txt", "valid content");
		write(projectRoot, "src/file.ts", "source");
		write(projectRoot, "subdir/file.txt", "content");

		eq(FileSystem.contains(projectRoot, NodePath.join(projectRoot, "src")), true, "contains child directory");
		eq(FileSystem.contains(projectRoot, NodePath.join(projectRoot, "src/file.ts")), true, "contains child file");
		eq(FileSystem.contains(projectRoot, projectRoot), true, "contains root");
		eq(FileSystem.contains(projectRoot, NodePath.join(projectRoot, "../etc")), false, "contains parent traversal");
		eq(FileSystem.contains(projectRoot, NodePath.join(projectRoot, "src/../../etc")), false, "contains nested traversal");
		eq(FileSystem.contains(projectRoot, "/etc/passwd"), false, "contains absolute outside");
		eq(FileSystem.contains(projectRoot, "/tmp/file"), false, "contains tmp outside");
		eq(FileSystem.contains(projectRoot, NodePath.join(root, "other")), false, "contains sibling outside");
		eq(FileSystem.contains(projectRoot, projectRoot + "-other/file"), false, "contains prefix collision directory");
		eq(FileSystem.contains(projectRoot, projectRoot + "file"), false, "contains prefix collision file");
		expectFailure(() -> FileSystem.read(projectRoot, "../../../etc/passwd"), "read passwd traversal");
		expectFailure(() -> FileSystem.read(projectRoot, "src/nested/../../../../../../../etc/passwd"), "read deep traversal");
		eq(FileSystem.read(projectRoot, "valid.txt").content, "valid content", "read valid path");
		expectFailure(() -> FileSystem.list(projectRoot, "../../../etc"), "list traversal");
		eq(FileSystem.list(projectRoot, "subdir").length, 1, "list valid subdirectory");

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
