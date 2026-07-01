package opencodehx.smoke;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import js.lib.Promise;
import js.lib.Uint8Array;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.node.Stream.NodeReadable;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.externs.web.WebStreams.WebReadableStreamDefaultController;
import opencodehx.externs.web.WebStreams.WebTextEncoder;
import opencodehx.file.AppFileSystem;
import opencodehx.file.AppFileSystem.AppFileContent;
import opencodehx.file.FileIgnore;
import opencodehx.file.FileSearchRuntime;
import opencodehx.file.FileSearchRuntime.FileSearchType;
import opencodehx.file.FileSystem;
import opencodehx.git.Git;
import opencodehx.host.node.NodeProcess;
import opencodehx.host.node.NodePath;
import opencodehx.smoke.SmokeCleanup.withCleanupAsync;
import opencodehx.smoke.SmokeCleanup.withCleanup;
import opencodehx.util.Compare.compareString;

class FileSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-file-"));
		withCleanup(() -> {
			fixture(root);
			appFileSystem(root);
			readFiles(root);
			readDiffs(root);
			fsmonitorGuard(root);
			ignoreRules();
			listWithIgnore(root);
			listEdges(root);
			fileSearch(root);
			pathSafety(root);
			ripgrepFiles(root);
			ripgrepSearch(root);
		}, () -> Fs.rmSync(root, {recursive: true, force: true}));
	}

	@:async
	public static function runAsync():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-file-async-"));
		@:await withCleanupAsync(() -> appFileSystemAsync(root), () -> Fs.rmSync(root, {recursive: true, force: true}));
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
		eq(AppFileSystem.isDir(file), false, "appfs isDir file");
		eq(AppFileSystem.size(file), 5, "appfs size file");
		eq(AppFileSystem.size(tmp) >= 0, true, "appfs size directory");
		eq(AppFileSystem.size(NodePath.join(tmp, "missing-size.txt")), 0, "appfs size missing");
		eq(AppFileSystem.readFileString(file), "hello", "appfs readText file");
		expectFailure(() -> AppFileSystem.readFileString(NodePath.join(tmp, "missing-read.txt")), "appfs readText missing");
		final unicodeFile = NodePath.join(tmp, "unicode.txt");
		AppFileSystem.writeFileString(unicodeFile, "Hello 世界 🌍");
		eq(AppFileSystem.readFileString(unicodeFile), "Hello 世界 🌍", "appfs readText utf8");

		final jsonFile = NodePath.join(tmp, "data.json");
		AppFileSystem.writeJson(jsonFile, genes.ts.Json.value({name: "test", count: 42}));
		final json = UnknownNarrow.record(AppFileSystem.readJson(jsonFile));
		if (json == null)
			throw "appfs readJson expected object";
		eq(UnknownNarrow.string(json.get("name")), "test", "appfs json name");
		eq(UnknownNarrow.number(json.get("count")), 42, "appfs json count");
		eq(AppFileSystem.readFileString(jsonFile).indexOf("\n") != -1, true, "appfs writeJson formatted newline");
		eq(AppFileSystem.readFileString(jsonFile).indexOf("  ") != -1, true, "appfs writeJson formatted spaces");
		final invalidJson = NodePath.join(tmp, "invalid.json");
		AppFileSystem.writeFileString(invalidJson, "{ invalid json");
		expectFailure(() -> AppFileSystem.readJson(invalidJson), "appfs readJson invalid");
		expectFailure(() -> AppFileSystem.readJson(NodePath.join(tmp, "missing.json")), "appfs readJson missing");

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
		final protectedText = NodePath.join(tmp, "protected.txt");
		AppFileSystem.writeWithDirs(protectedText, Text("secret"), 0x180);
		if (NodeProcess.platform() != "win32")
			eq(Fs.statSync(protectedText).mode & 0x1ff, 0x180, "appfs writeWithDirs text mode");
		final binaryFile = NodePath.join(tmp, "binary.bin");
		AppFileSystem.writeWithDirs(binaryFile, Bytes(js.lib.Uint8Array.from([0x00, 0x01, 0x02, 0x03])));
		final binary = AppFileSystem.readFile(binaryFile).subarray(0);
		eq(binary.length, 4, "appfs binary length");
		eq(binary[0], 0, "appfs binary byte 0");
		eq(binary[3], 3, "appfs binary byte 3");
		expectFailure(() -> AppFileSystem.readFile(NodePath.join(tmp, "missing.bin")), "appfs readBytes missing");
		final protectedBinary = NodePath.join(tmp, "protected.bin");
		AppFileSystem.writeWithDirs(protectedBinary, Bytes(js.lib.Uint8Array.from([0x00, 0x01])), 0x180);
		if (NodeProcess.platform() != "win32")
			eq(Fs.statSync(protectedBinary).mode & 0x1ff, 0x180, "appfs writeWithDirs binary mode");
		final protectedJson = NodePath.join(tmp, "protected.json");
		AppFileSystem.writeJson(protectedJson, genes.ts.Json.value({secret: "data"}), 0x180);
		if (NodeProcess.platform() != "win32")
			eq(Fs.statSync(protectedJson).mode & 0x1ff, 0x180, "appfs writeJson mode");

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
		AppFileSystem.writeFileString(NodePath.join(tmp, "cfg.json"), "{}");
		AppFileSystem.writeFileString(NodePath.join(tmp, "cfg.jsonc"), "{}");
		AppFileSystem.writeFileString(NodePath.join(child, "cfg.jsonc"), "{}");
		eq(AppFileSystem.findUpMany(["cfg.json", "cfg.jsonc"], child, tmp).join("|"), [
			NodePath.join(child, "cfg.jsonc"),
			NodePath.join(tmp, "cfg.json"),
			NodePath.join(tmp, "cfg.jsonc")
		].join("|"), "appfs findUpMany nearest first");
		eq(AppFileSystem.findUpMany(["cfg.json", "cfg.jsonc"], child, tmp, {rootFirst: true}).join("|"), [
			NodePath.join(tmp, "cfg.json"),
			NodePath.join(tmp, "cfg.jsonc"),
			NodePath.join(child, "cfg.jsonc")
		].join("|"), "appfs findUpMany root first");

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
		eq(AppFileSystem.mimeType("file.js").indexOf("javascript") != -1, true, "appfs mime js");
		final tsMime = AppFileSystem.mimeType("file.ts");
		eq(tsMime == "video/mp2t" || tsMime == "application/typescript" || tsMime == "text/typescript", true, "appfs mime ts");
		eq(AppFileSystem.mimeType("image.png"), "image/png", "appfs mime png");
		eq(AppFileSystem.mimeType("image.jpg"), "image/jpeg", "appfs mime jpg");
		eq(AppFileSystem.mimeType("unknown.qzx"), "application/octet-stream", "appfs mime unknown");
		eq(AppFileSystem.mimeType("Makefile"), "application/octet-stream", "appfs mime no extension");
		eq(AppFileSystem.contains("/a/b", "/a/b/c"), true, "appfs contains true");
		eq(AppFileSystem.contains("/a/b", "/a/c"), false, "appfs contains false");
		eq(AppFileSystem.overlaps("/a/b", "/a/b/c"), true, "appfs overlaps child");
		eq(AppFileSystem.overlaps("/a/b/c", "/a/b"), true, "appfs overlaps parent");
		eq(AppFileSystem.overlaps("/a", "/b"), false, "appfs overlaps false");
		eq(AppFileSystem.windowsPath("/c/Users/test"), NodeProcess.platform() == "win32" ? "C:/Users/test" : "/c/Users/test", "appfs windowsPath git bash");
		eq(AppFileSystem.windowsPath("/d/dev/project"), NodeProcess.platform() == "win32" ? "D:/dev/project" : "/d/dev/project",
			"appfs windowsPath git bash d");
		eq(AppFileSystem.windowsPath("/cygdrive/c/Users/test"), NodeProcess.platform() == "win32" ? "C:/Users/test" : "/cygdrive/c/Users/test",
			"appfs windowsPath cygwin");
		eq(AppFileSystem.windowsPath("/cygdrive/x/dev/project"), NodeProcess.platform() == "win32" ? "X:/dev/project" : "/cygdrive/x/dev/project",
			"appfs windowsPath cygwin x");
		eq(AppFileSystem.windowsPath("/mnt/c/Users/test"), NodeProcess.platform() == "win32" ? "C:/Users/test" : "/mnt/c/Users/test", "appfs windowsPath wsl");
		eq(AppFileSystem.windowsPath("/mnt/z/dev/project"), NodeProcess.platform() == "win32" ? "Z:/dev/project" : "/mnt/z/dev/project",
			"appfs windowsPath wsl z");
		eq(AppFileSystem.windowsPath("C:/Users/test"), "C:/Users/test", "appfs windowsPath normal");
		eq(AppFileSystem.windowsPath("D:\\dev\\project"), "D:\\dev\\project", "appfs windowsPath backslash normal");
		eq(AppFileSystem.normalizePathPattern("*"), "*", "appfs normalizePathPattern star");
		if (NodeProcess.platform() != "win32") {
			eq(AppFileSystem.normalizePath("/c/Users/test"), "/c/Users/test", "appfs normalizePath nonwindows");
			eq(AppFileSystem.normalizePathPattern("/tmp/*"), "/tmp/*", "appfs normalizePathPattern nonwindows");
		}
		final resolvedTmp = AppFileSystem.resolve(tmp);
		eq(resolvedTmp, AppFileSystem.normalizePath(Fs.realpathSync(tmp)), "appfs resolve existing");
		final missing = NodePath.join(tmp, "does-not-exist-for-resolve");
		eq(AppFileSystem.resolve(missing), AppFileSystem.normalizePath(NodePath.resolve(missing, ".")), "appfs resolve missing fallback");
	}

	@:async
	static function appFileSystemAsync(root:String):Promise<Void> {
		final streamFile = NodePath.join(root, "streamed.txt");
		@:await AppFileSystem.writeStream(streamFile, webStream(["Hello from stream!"]));
		eq(AppFileSystem.readFileString(streamFile), "Hello from stream!", "appfs writeStream web text");

		final nodeStreamFile = NodePath.join(root, "node-streamed.txt");
		@:await AppFileSystem.writeNodeStream(nodeStreamFile, NodeReadable.from(["Hello from Node stream!"]));
		eq(AppFileSystem.readFileString(nodeStreamFile), "Hello from Node stream!", "appfs writeStream node text");

		final binaryFile = NodePath.join(root, "binary.dat");
		@:await AppFileSystem.writeStream(binaryFile, webBinaryStream([Uint8Array.from([0x00, 0x01, 0x02, 0x03, 0xff])]));
		final binary = AppFileSystem.readFile(binaryFile).subarray(0);
		eq(binary.length, 5, "appfs writeStream binary length");
		eq(binary[4], 0xff, "appfs writeStream binary byte");

		final largeFile = NodePath.join(root, "large.txt");
		@:await AppFileSystem.writeStream(largeFile, webStream(["chunk1", "chunk2", "chunk3", "chunk4", "chunk5"]));
		eq(AppFileSystem.readFileString(largeFile), "chunk1chunk2chunk3chunk4chunk5", "appfs writeStream chunks");

		final nested = NodePath.join(NodePath.join(NodePath.join(root, "nested"), "deep"), "streamed.txt");
		@:await AppFileSystem.writeStream(nested, webStream(["nested stream content"]));
		eq(AppFileSystem.readFileString(nested), "nested stream content", "appfs writeStream creates parents");

		final protectedFile = NodePath.join(root, "protected-stream.txt");
		@:await AppFileSystem.writeStream(protectedFile, webStream(["secret stream content"]), 0x180);
		eq(AppFileSystem.readFileString(protectedFile), "secret stream content", "appfs writeStream protected content");
		if (NodeProcess.platform() != "win32")
			eq(Fs.statSync(protectedFile).mode & 0x1ff, 0x180, "appfs writeStream protected mode");

		final executable = NodePath.join(root, "script.sh");
		@:await AppFileSystem.writeStream(executable, webStream(["#!/bin/bash\necho hello"]), 0x1ed);
		eq(AppFileSystem.readFileString(executable), "#!/bin/bash\necho hello", "appfs writeStream executable content");
		if (NodeProcess.platform() != "win32")
			eq(Fs.statSync(executable).mode & 0x1ff, 0x1ed, "appfs writeStream executable mode");

		if (NodeProcess.platform() != "win32") {
			final target = NodePath.join(root, "real");
			AppFileSystem.ensureDir(target);
			final link = NodePath.join(root, "link");
			Fs.symlinkSync(target, link);
			eq(AppFileSystem.resolve(link), AppFileSystem.resolve(target), "appfs resolve symlink canonical");

			final cycleA = NodePath.join(root, "cycle-a");
			final cycleB = NodePath.join(root, "cycle-b");
			Fs.symlinkSync(cycleB, cycleA);
			Fs.symlinkSync(cycleA, cycleB);
			expectFailure(() -> AppFileSystem.resolve(cycleA), "appfs resolve symlink cycle");

			if (NodeProcess.uid() != 0) {
				final restricted = NodePath.join(root, "restricted");
				AppFileSystem.ensureDir(restricted);
				final restrictedLink = NodePath.join(root, "restricted-link");
				Fs.symlinkSync(restricted, restrictedLink);
				Fs.chmodSync(restricted, 0);
				withCleanup(() -> {
					expectFailure(() -> AppFileSystem.resolve(NodePath.join(restrictedLink, "child")), "appfs resolve permission denied symlink");
				}, () -> Fs.chmodSync(restricted, 0x1ed));
			}

			final file = NodePath.join(root, "not-a-directory");
			AppFileSystem.writeFileString(file, "x");
			expectFailure(() -> AppFileSystem.resolve(NodePath.join(file, "child")), "appfs resolve non-ENOENT");
		}
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

	static function readDiffs(root:String):Void {
		final repo = NodePath.join(root, "read-diff");
		Fs.mkdirSync(repo, {recursive: true});
		git(repo, ["init"], "read diff init");
		git(repo, ["config", "user.email", "opencodehx@example.invalid"], "read diff git email");
		git(repo, ["config", "user.name", "OpenCodeHX Smoke"], "read diff git name");
		write(repo, "file.txt", "original content\n");
		write(repo, "staged.txt", "before\n");
		write(repo, "clean.txt", "unchanged\n");
		writeBytes(repo, "data.bin", [0x00, 0x01, 0x02, 0x03]);
		git(repo, ["add", "."], "read diff add initial");
		git(repo, ["commit", "-m", "initial"], "read diff commit initial");

		write(repo, "file.txt", "modified content\n");
		final modified = FileSystem.read(repo, "file.txt");
		eq(modified.content, "modified content", "read diff modified content");
		eq(modified.diff.indexOf("original content") != -1, true, "read diff modified original");
		eq(modified.diff.indexOf("modified content") != -1, true, "read diff modified current");
		eq(modified.patch != null, true, "read diff modified patch");
		eq(modified.patch.hunks.length > 0, true, "read diff modified hunks");

		write(repo, "staged.txt", "after\n");
		git(repo, ["add", "staged.txt"], "read diff staged add");
		final staged = FileSystem.read(repo, "staged.txt");
		eq(staged.diff.indexOf("before") != -1, true, "read diff staged original");
		eq(staged.diff.indexOf("after") != -1, true, "read diff staged current");
		eq(staged.patch != null, true, "read diff staged patch");
		eq(staged.patch.hunks.length > 0, true, "read diff staged hunks");

		final clean = FileSystem.read(repo, "clean.txt");
		eq(clean.content, "unchanged", "read diff clean content");
		eq(clean.diff, null, "read diff clean no diff");
		eq(clean.patch, null, "read diff clean no patch");

		writeBytes(repo, "data.bin", [0x00, 0x01, 0x02, 0x03, 0x04]);
		final binary = FileSystem.read(repo, "data.bin");
		eq(binary.type, "binary", "read diff binary type");
		eq(binary.diff, null, "read diff binary no diff");
		eq(binary.patch, null, "read diff binary no patch");
	}

	static function fsmonitorGuard(root:String):Void {
		eq(hasGitConfigArg(Git.baseArgs(), "core.fsmonitor=false"), true, "git fsmonitor disabled base arg");

		final repo = NodePath.join(root, "fsmonitor");
		Fs.mkdirSync(repo, {recursive: true});
		git(repo, ["init"], "fsmonitor init");
		git(repo, ["config", "user.email", "opencodehx@example.invalid"], "fsmonitor git email");
		git(repo, ["config", "user.name", "OpenCodeHX Smoke"], "fsmonitor git name");
		write(repo, "tracked.txt", "base\n");
		git(repo, ["add", "."], "fsmonitor add initial");
		git(repo, ["commit", "-m", "initial"], "fsmonitor commit initial");
		git(repo, ["config", "core.fsmonitor", "true"], "fsmonitor enable config");
		Git.run(repo, ["fsmonitor--daemon", "stop"]);
		write(repo, "tracked.txt", "next\n");
		write(repo, "new.txt", "new\n");

		final before = Git.run(repo, ["fsmonitor--daemon", "status"]);
		eq(Git.status(repo).length > 0, true, "fsmonitor status works");
		final read = FileSystem.read(repo, "tracked.txt");
		eq(read.content, "next", "fsmonitor read works");
		eq(read.diff.indexOf("base") != -1, true, "fsmonitor read diff");
		final after = Git.run(repo, ["fsmonitor--daemon", "status"]);
		if (NodeProcess.platform() == "win32" && before.code != 0)
			neq(after.code, 0, "fsmonitor daemon remains stopped");
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
		withCleanup(() -> {
			write(plain, "file.txt", "hi");
			for (node in FileSystem.list(plain))
				eq(node.ignored, false, "list without ignore marks false");
		}, () -> Fs.rmSync(plain, {recursive: true, force: true}));
	}

	static function fileSearch(root:String):Void {
		final searchRoot = NodePath.join(root, "search");
		write(searchRoot, "index.ts", "code");
		write(searchRoot, "utils.ts", "utils");
		write(searchRoot, "readme.md", "readme");
		write(searchRoot, "src/main.ts", "main");
		write(searchRoot, ".hidden/secret.ts", "secret");

		final files = FileSearchRuntime.search(searchRoot, {query: "", type: FileSearchType.File});
		eq(files.length > 0, true, "file search empty files");
		for (file in files)
			eq(StringTools.endsWith(file, "/"), false, "file search file type");

		final beforeInit = FileSearchRuntime.search(searchRoot, {query: "main", type: FileSearchType.File});
		eq(beforeInit.indexOf("src/main.ts") != -1, true, "file search before init");

		final dirs = FileSearchRuntime.search(searchRoot, {query: "", type: FileSearchType.Directory});
		eq(dirs.length > 0, true, "file search empty directories");
		for (dir in dirs)
			eq(StringTools.endsWith(dir, "/"), true, "file search directory type");
		final firstHidden = firstHiddenIndex(dirs);
		final lastVisible = lastVisibleIndex(dirs);
		if (firstHidden >= 0 && lastVisible >= 0)
			eq(firstHidden > lastVisible, true, "file search hidden directories last");

		final fuzzy = FileSearchRuntime.search(searchRoot, {query: "mn", type: FileSearchType.File});
		eq(fuzzy.indexOf("src/main.ts") != -1, true, "file search fuzzy filename");

		final limited = FileSearchRuntime.search(searchRoot, {query: "", type: FileSearchType.File, limit: 2});
		eq(limited.length <= 2, true, "file search limit");

		final hidden = FileSearchRuntime.search(searchRoot, {query: ".hidden", type: FileSearchType.Directory});
		eq(hidden.length > 0, true, "file search dot query");
		eq(hidden[0].indexOf(".hidden") != -1, true, "file search hidden preferred");

		eq(FileSearchRuntime.search(searchRoot, {query: "fresh", type: FileSearchType.File}).length, 0, "file search fresh absent");
		write(searchRoot, "fresh.ts", "fresh");
		eq(FileSearchRuntime.search(searchRoot, {query: "fresh", type: FileSearchType.File}).indexOf("fresh.ts") != -1, true, "file search refresh");

		final one = NodePath.join(root, "search-one");
		final two = NodePath.join(root, "search-two");
		write(one, "a.ts", "one");
		write(two, "b.ts", "two");
		eq(FileSearchRuntime.search(one, {query: "a.ts", type: FileSearchType.File}).join(","), "a.ts", "file search root one match");
		eq(FileSearchRuntime.search(one, {query: "b.ts", type: FileSearchType.File}).length, 0, "file search root one isolated");
		eq(FileSearchRuntime.search(two, {query: "b.ts", type: FileSearchType.File}).join(","), "b.ts", "file search root two match");
		eq(FileSearchRuntime.search(two, {query: "a.ts", type: FileSearchType.File}).length, 0, "file search root two isolated");
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
		write(root, "rg/visible.txt", "hello");
		write(root, "rg/.opencode/thing.json", "{}");
		write(root, "rg/a.txt", "hello");
		write(root, "rg/b.txt", "world");
		write(root, "rg/keep.ts", "yes");
		write(root, "rg/skip.txt", "no");
		write(root, "rg/packages/console/package.json", "{}");

		final defaultHidden = FileSystem.files(NodePath.join(root, "rg"));
		eq(defaultHidden.indexOf("visible.txt") != -1, true, "rg files default visible");
		eq(defaultHidden.indexOf(".opencode/thing.json") != -1, true, "rg files default hidden");
		final hiddenFalse = FileSystem.files(NodePath.join(root, "rg"), null, false);
		eq(hiddenFalse.indexOf("visible.txt") != -1, true, "rg files hidden false visible");
		eq(hiddenFalse.indexOf(".opencode/thing.json") == -1, true, "rg files hidden false excludes hidden");
		eq(FileSystem.files(NodePath.join(root, "rg"), ["packages/*"]).length, 0, "rg files glob no files");
		final listed = FileSystem.files(NodePath.join(root, "rg"), ["*.txt"]);
		listed.sort(compareString);
		eq(listed.join(","), "a.txt,b.txt,skip.txt,visible.txt", "rg files sorted filenames");
		eq(FileSystem.files(NodePath.join(root, "rg"), ["*.ts"]).join(","), "keep.ts", "rg files glob filter");
		expectFailure(() -> FileSystem.files(NodePath.join(root, "missing-rg")), "rg files missing cwd");

		final visible = FileSystem.files(root, ["*.ts"], false);
		eq(visible.indexOf("src/main.ts") != -1, true, "rg files glob");
		eq(visible.indexOf(".hidden/config") == -1, true, "hidden filtered");

		final hidden = FileSystem.files(root, [".hidden/*"], true);
		eq(hidden.indexOf(".hidden/config") != -1, true, "hidden included");
	}

	static function ripgrepSearch(root:String):Void {
		write(root, "rg-search/match.ts", "const value = 'needle'\n");
		write(root, "rg-search/skip.ts", "const value = 'needle'\n");
		write(root, "rg-search/skip.txt", "const value = 'other'\n");
		final empty = FileSystem.search(NodePath.join(root, "rg-search"), "absent");
		eq(empty.partial, false, "rg search empty not partial");
		eq(empty.items.length, 0, "rg search empty items");
		final globbed = FileSystem.search(NodePath.join(root, "rg-search"), "needle", ["*.ts"]);
		eq(globbed.partial, false, "rg search glob not partial");
		eq(globbed.items.length, 2, "rg search glob match count");
		eq(globbed.items[0].path.indexOf(".ts") != -1, true, "rg search glob path");
		eq(globbed.items[0].line.indexOf("needle") != -1, true, "rg search glob line");
		final explicit = opencodehx.file.Ripgrep.search({
			cwd: NodePath.join(root, "rg-search"),
			pattern: "needle",
			file: [NodePath.join(NodePath.join(root, "rg-search"), "match.ts")]
		});
		eq(explicit.partial, false, "rg search explicit file not partial");
		eq(explicit.items.length, 1, "rg search explicit file count");
		eq(explicit.items[0].path, NodePath.join(NodePath.join(root, "rg-search"), "match.ts"), "rg search explicit file path");
		final originalConfig = NodeProcess.envValue("RIPGREP_CONFIG_PATH");
		NodeProcess.setEnv("RIPGREP_CONFIG_PATH", NodePath.join(root, "missing-ripgreprc"));
		withCleanup(() -> {
			eq(FileSystem.search(NodePath.join(root, "rg-search"), "needle").items.length, 2, "rg search ignores config path");
		}, () -> restoreEnv("RIPGREP_CONFIG_PATH", originalConfig));

		final result = FileSystem.search(root, "needle", ["src/*.ts"], 5);
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

	static function git(cwd:String, args:Array<String>, label:String):Void {
		final result = Git.run(cwd, args);
		if (result.code != 0)
			throw '${label}: ${result.stderr}';
	}

	static function hasGitConfigArg(args:Array<String>, value:String):Bool {
		for (i in 0...args.length - 1) {
			if (args[i] == "-c" && args[i + 1] == value)
				return true;
		}
		return false;
	}

	static function findNode(nodes:Array<opencodehx.file.FileSystem.FileNode>, name:String):opencodehx.file.FileSystem.FileNode {
		for (node in nodes) {
			if (node.name == name)
				return node;
		}
		throw 'missing node ${name}';
	}

	static function firstHiddenIndex(paths:Array<String>):Int {
		for (i in 0...paths.length) {
			if (hasHiddenSegment(paths[i]))
				return i;
		}
		return -1;
	}

	static function lastVisibleIndex(paths:Array<String>):Int {
		var result = -1;
		for (i in 0...paths.length) {
			if (!hasHiddenSegment(paths[i]))
				result = i;
		}
		return result;
	}

	static function hasHiddenSegment(path:String):Bool {
		for (part in path.split("/")) {
			if (part.length > 1 && StringTools.startsWith(part, "."))
				return true;
		}
		return false;
	}

	static function webStream(chunks:Array<String>):WebReadableStream<Uint8Array> {
		final encoder = new WebTextEncoder();
		return new WebReadableStream<Uint8Array>({
			start: (controller:WebReadableStreamDefaultController<Uint8Array>) -> {
				for (chunk in chunks)
					controller.enqueue(encoder.encode(chunk));
				controller.close();
			}
		});
	}

	static function webBinaryStream(chunks:Array<Uint8Array>):WebReadableStream<Uint8Array> {
		return new WebReadableStream<Uint8Array>({
			start: (controller:WebReadableStreamDefaultController<Uint8Array>) -> {
				for (chunk in chunks)
					controller.enqueue(chunk);
				controller.close();
			}
		});
	}

	static function expectFailure(run:() -> Void, label:String):Void {
		try {
			run();
		} catch (_:Dynamic) {
			return;
		}
		throw '${label}: expected failure';
	}

	static function restoreEnv(key:String, value:Null<String>):Void {
		if (value == null)
			NodeProcess.unsetEnv(key);
		else
			NodeProcess.setEnv(key, value);
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}

	static function neq<T>(actual:T, expected:T, label:String):Void {
		if (actual == expected) {
			throw '$label: expected value other than ${expected}';
		}
	}
}
