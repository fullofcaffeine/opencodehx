package opencodehx.smoke;

import opencodehx.externs.node.Fs;
import opencodehx.git.Git;
import opencodehx.git.Git.GitRunResult;
import opencodehx.host.node.NodePath;
import opencodehx.snapshot.SnapshotRuntime;
import opencodehx.snapshot.SnapshotRuntime.SnapshotPatch;

class SnapshotSmoke {
	public static function run():Void {
		SnapshotRuntime.reset();
		patchAndRevert();
		emptyDirectoryAndInvalidHash();
		largeAddedFilesAreSkipped();
		gitignoreFiltering();
		SnapshotRuntime.reset();
	}

	static function patchAndRevert():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		write(dir, "c.txt", "C");
		write(dir, "b.txt", "MODIFIED");
		Fs.rmSync(NodePath.join(dir, "a.txt"), {force: true});

		final patch = SnapshotRuntime.patch(dir, before);
		contains(patch, dir, "a.txt", "snapshot deleted file");
		contains(patch, dir, "b.txt", "snapshot modified file");
		contains(patch, dir, "c.txt", "snapshot added file");
		final diff = SnapshotRuntime.diff(dir, before);
		eq(diff.indexOf("a.txt") != -1, true, "snapshot diff deleted");
		eq(diff.indexOf("b.txt") != -1, true, "snapshot diff modified");
		eq(diff.indexOf("c.txt") != -1, true, "snapshot diff added");

		SnapshotRuntime.revert(dir, [patch]);
		eq(Fs.readFileSync(NodePath.join(dir, "a.txt"), "utf8"), "A", "snapshot revert deleted");
		eq(Fs.readFileSync(NodePath.join(dir, "b.txt"), "utf8"), "B", "snapshot revert modified");
		eq(Fs.existsSync(NodePath.join(dir, "c.txt")), false, "snapshot revert added");
		tmp.dispose();
	}

	static function emptyDirectoryAndInvalidHash():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		Fs.mkdirSync(NodePath.join(dir, "empty"), {recursive: true});
		eq(SnapshotRuntime.patch(dir, before).files.length, 0, "snapshot empty directory ignored");
		final invalid = SnapshotRuntime.patch(dir, "invalid-hash-12345");
		eq(invalid.hash, "invalid-hash-12345", "snapshot invalid hash returned");
		eq(invalid.files.length, 0, "snapshot invalid hash no files");
		SnapshotRuntime.revert(dir, []);
		SnapshotRuntime.revert(dir, [{hash: "missing", files: []}]);
		tmp.dispose();
	}

	static function largeAddedFilesAreSkipped():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		write(dir, "huge.txt", repeat("x", 2 * 1024 * 1024 + 1));
		eq(SnapshotRuntime.patch(dir, before).files.length, 0, "snapshot large added skipped");
		eq(SnapshotRuntime.diff(dir, before), "", "snapshot large added diff skipped");
		eq(SnapshotRuntime.trackDirectory(dir), before, "snapshot large added stable hash");
		tmp.dispose();
	}

	static function gitignoreFiltering():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		write(dir, ".gitignore", "*.ignored\nbuild/\n");
		write(dir, "normal.txt", "normal");
		write(dir, "test.ignored", "ignored");
		write(join(dir, "build"), "output.js", "ignored build");

		final patch = SnapshotRuntime.patch(dir, before);
		contains(patch, dir, ".gitignore", "snapshot gitignore file");
		contains(patch, dir, "normal.txt", "snapshot normal file");
		missing(patch, dir, "test.ignored", "snapshot ignored file");
		missing(patch, dir, "build/output.js", "snapshot ignored directory file");

		final after = SnapshotRuntime.trackDirectory(dir);
		final diffs = SnapshotRuntime.diffFull(dir, before, after);
		eq(hasDiff(diffs, ".gitignore"), true, "snapshot diffFull gitignore");
		eq(hasDiff(diffs, "normal.txt"), true, "snapshot diffFull normal");
		eq(hasDiff(diffs, "test.ignored"), false, "snapshot diffFull ignored");
		tmp.dispose();
	}

	static function bootstrap():SmokeTmpDir {
		final tmp = SmokeTmpDir.create({git: true});
		final dir = tmp.path;
		write(dir, "a.txt", "A");
		write(dir, "b.txt", "B");
		require(Git.run(dir, ["add", "."]), "snapshot bootstrap add");
		require(Git.run(dir, [
			"-c",
			"user.email=opencodehx@example.invalid",
			"-c",
			"user.name=OpenCodeHX Smoke",
			"commit",
			"-m",
			"init"
		]), "snapshot bootstrap commit");
		return tmp;
	}

	static function contains(patch:SnapshotPatch, dir:String, file:String, label:String):Void {
		eq(patch.files.indexOf(abs(dir, file)) != -1, true, label);
	}

	static function missing(patch:SnapshotPatch, dir:String, file:String, label:String):Void {
		eq(patch.files.indexOf(abs(dir, file)) == -1, true, label);
	}

	static function hasDiff(diffs:Array<opencodehx.snapshot.SnapshotRuntime.SnapshotFileDiff>, file:String):Bool {
		for (diff in diffs) {
			if (diff.file == file)
				return true;
		}
		return false;
	}

	static function abs(dir:String, file:String):String {
		return NodePath.resolve(NodePath.join(dir, file), "").split("\\").join("/");
	}

	static function join(first:String, second:String):String {
		return NodePath.join(first, second);
	}

	static function write(root:String, relative:String, content:String):Void {
		final path = NodePath.join(root, relative);
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, content);
	}

	static function repeat(text:String, count:Int):String {
		var out = "";
		var chunk = text;
		var remaining = count;
		while (remaining > 0) {
			if ((remaining & 1) == 1)
				out += chunk;
			remaining = remaining >> 1;
			if (remaining > 0)
				chunk += chunk;
		}
		return out;
	}

	static function require(result:GitRunResult, label:String):Void {
		if (result.code != 0)
			throw '${label}: ${result.stderr}';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
