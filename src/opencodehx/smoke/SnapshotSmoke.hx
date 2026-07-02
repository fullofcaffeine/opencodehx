package opencodehx.smoke;

import js.lib.Uint8Array;
import opencodehx.externs.node.Buffer;
import opencodehx.externs.node.Fs;
import opencodehx.git.Git;
import opencodehx.git.Git.GitRunResult;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.snapshot.SnapshotRuntime;
import opencodehx.snapshot.SnapshotRuntime.SnapshotPatch;

class SnapshotSmoke {
	public static function run():Void {
		SnapshotRuntime.reset();
		patchAndRevert();
		restoreSnapshot();
		recreatedFileRevert();
		nestedDirectoryRevert();
		overlappingRevertOrder();
		largeBatchRevert();
		emptyDirectoryAndInvalidHash();
		revertNonExistentFile();
		underLimitAddedFilesAreTracked();
		specialFilenamePatchDetection();
		hiddenFilePatchDetection();
		permissionChangesAreIgnored();
		largeAddedFilesAreSkipped();
		gitignoreFiltering();
		newlyIgnoredSnapshotFileFiltering();
		gitInfoExcludeFiltering();
		gitInfoExcludeKeepsGlobalExcludes();
		projectStateIsolation();
		secondaryWorktreePatchDetection();
		secondaryWorktreeRevertIsolation();
		binaryDiffFull();
		binaryPatchAndRevert();
		symlinkPatch();
		diffFullNoChanges();
		diffFullOrderAcrossBatchBoundaries();
		diffFullStatuses();
		repeatedTrackStableHash();
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

	static function restoreSnapshot():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		Fs.rmSync(NodePath.join(dir, "a.txt"), {force: true});
		write(dir, "new.txt", "new content");
		write(dir, "b.txt", "modified");

		SnapshotRuntime.restore(dir, before);
		eq(Fs.readFileSync(NodePath.join(dir, "a.txt"), "utf8"), "A", "snapshot restore deleted file");
		eq(Fs.readFileSync(NodePath.join(dir, "b.txt"), "utf8"), "B", "snapshot restore modified file");
		eq(Fs.readFileSync(NodePath.join(dir, "new.txt"), "utf8"), "new content", "snapshot restore leaves new file");
		tmp.dispose();
	}

	static function recreatedFileRevert():Void {
		final deleted = bootstrap();
		final deletedDir = deleted.path;
		final first = SnapshotRuntime.trackDirectory(deletedDir);
		Fs.rmSync(NodePath.join(deletedDir, "a.txt"), {force: true});
		final deletedSnapshot = SnapshotRuntime.trackDirectory(deletedDir);
		write(deletedDir, "a.txt", "recreated content");
		final deletedPatch = SnapshotRuntime.patch(deletedDir, deletedSnapshot);
		contains(deletedPatch, deletedDir, "a.txt", "snapshot recreated deleted-in-snapshot file");
		SnapshotRuntime.revert(deletedDir, [deletedPatch]);
		eq(Fs.existsSync(NodePath.join(deletedDir, "a.txt")), false, "snapshot revert removes recreated deleted-in-snapshot file");
		eq(first != deletedSnapshot, true, "snapshot deleted-file hash changes");
		deleted.dispose();

		final restored = bootstrap();
		final restoredDir = restored.path;
		write(restoredDir, "existing.txt", "original content");
		final snapshot = SnapshotRuntime.trackDirectory(restoredDir);
		Fs.rmSync(NodePath.join(restoredDir, "existing.txt"), {force: true});
		write(restoredDir, "existing.txt", "recreated");
		write(restoredDir, "newfile.txt", "new");
		final restoredPatch = SnapshotRuntime.patch(restoredDir, snapshot);
		contains(restoredPatch, restoredDir, "existing.txt", "snapshot recreated existing file");
		contains(restoredPatch, restoredDir, "newfile.txt", "snapshot recreated new file");
		SnapshotRuntime.revert(restoredDir, [restoredPatch]);
		eq(Fs.existsSync(NodePath.join(restoredDir, "newfile.txt")), false, "snapshot revert removes recreated new file");
		eq(Fs.readFileSync(NodePath.join(restoredDir, "existing.txt"), "utf8"), "original content", "snapshot revert restores recreated existing file");
		restored.dispose();
	}

	static function nestedDirectoryRevert():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		write(dir, "level1/level2/level3/deep.txt", "DEEP");
		final patch = SnapshotRuntime.patch(dir, before);
		contains(patch, dir, "level1/level2/level3/deep.txt", "snapshot nested added file");
		SnapshotRuntime.revert(dir, [patch]);
		eq(Fs.existsSync(NodePath.join(dir, "level1/level2/level3/deep.txt")), false, "snapshot nested revert removes added file");
		tmp.dispose();
	}

	static function overlappingRevertOrder():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		write(dir, "shared.txt", "v1");
		final snap1 = SnapshotRuntime.trackDirectory(dir);
		write(dir, "shared.txt", "v2");
		final snap2 = SnapshotRuntime.trackDirectory(dir);
		write(dir, "shared.txt", "v3");

		final patch1 = SnapshotRuntime.patch(dir, snap1);
		final patch2 = SnapshotRuntime.patch(dir, snap2);
		contains(patch1, dir, "shared.txt", "snapshot overlapping first patch");
		contains(patch2, dir, "shared.txt", "snapshot overlapping second patch");
		SnapshotRuntime.revert(dir, [patch1, patch2]);
		eq(Fs.readFileSync(NodePath.join(dir, "shared.txt"), "utf8"), "v1", "snapshot overlapping revert uses first patch");
		tmp.dispose();
	}

	static function largeBatchRevert():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		for (i in 0...140)
			write(dir, "batch/" + i + ".txt", "base-" + i);

		final snapshot = SnapshotRuntime.trackDirectory(dir);
		for (i in 0...140) {
			write(dir, "batch/" + i + ".txt", "next-" + i);
			write(dir, "fresh/" + i + ".txt", "fresh-" + i);
		}

		final patch = SnapshotRuntime.patch(dir, snapshot);
		eq(patch.files.length, 280, "snapshot large batch patch count");
		SnapshotRuntime.revert(dir, [patch]);
		for (i in 0...140) {
			eq(Fs.readFileSync(NodePath.join(dir, "batch/" + i + ".txt"), "utf8"), "base-" + i, "snapshot large batch restored " + i);
			eq(Fs.existsSync(NodePath.join(dir, "fresh/" + i + ".txt")), false, "snapshot large batch removed fresh " + i);
		}
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

	static function revertNonExistentFile():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		final missingFile = abs(dir, "nonexistent.txt");
		SnapshotRuntime.revert(dir, [{hash: before, files: [missingFile]}]);
		eq(Fs.existsSync(missingFile), false, "snapshot revert ignores non-existent file");
		tmp.dispose();
	}

	static function underLimitAddedFilesAreTracked():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		write(dir, "large.txt", repeat("x", 1024 * 1024));
		final patch = SnapshotRuntime.patch(dir, before);
		contains(patch, dir, "large.txt", "snapshot under-limit added file");
		tmp.dispose();
	}

	static function specialFilenamePatchDetection():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		write(dir, "file with spaces.txt", "SPACES");
		write(dir, "file-with-dashes.txt", "DASHES");
		write(dir, "file_with_underscores.txt", "UNDERSCORES");

		final patch = SnapshotRuntime.patch(dir, before);
		contains(patch, dir, "file with spaces.txt", "snapshot special filename spaces");
		contains(patch, dir, "file-with-dashes.txt", "snapshot special filename dashes");
		contains(patch, dir, "file_with_underscores.txt", "snapshot special filename underscores");
		tmp.dispose();
	}

	static function hiddenFilePatchDetection():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		write(dir, ".hidden", "hidden content");
		write(dir, ".gitignore", "*.log");
		write(dir, ".config", "config content");

		final patch = SnapshotRuntime.patch(dir, before);
		contains(patch, dir, ".hidden", "snapshot hidden file");
		contains(patch, dir, ".gitignore", "snapshot hidden gitignore file");
		contains(patch, dir, ".config", "snapshot hidden config file");
		tmp.dispose();
	}

	static function permissionChangesAreIgnored():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final file = NodePath.join(dir, "a.txt");
		final before = SnapshotRuntime.trackDirectory(dir);
		Fs.chmodSync(file, 0x180);
		Fs.chmodSync(file, 0x1ed);
		Fs.chmodSync(file, 0x1a4);
		eq(SnapshotRuntime.patch(dir, before).files.length, 0, "snapshot chmod-only changes ignored");
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

	static function newlyIgnoredSnapshotFileFiltering():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		write(dir, "later-ignored.txt", "initial content");
		final before = SnapshotRuntime.trackDirectory(dir);
		write(dir, "later-ignored.txt", "modified content");
		write(dir, ".gitignore", "later-ignored.txt\n");
		write(dir, "still-tracked.txt", "new tracked file");

		final patch = SnapshotRuntime.patch(dir, before);
		missing(patch, dir, "later-ignored.txt", "snapshot newly ignored tracked file");
		contains(patch, dir, ".gitignore", "snapshot newly ignored gitignore file");
		contains(patch, dir, "still-tracked.txt", "snapshot newly ignored still-tracked file");
		tmp.dispose();
	}

	static function gitInfoExcludeFiltering():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		final exclude = NodePath.join(dir, ".git/info/exclude");
		final text = Fs.readFileSync(exclude, "utf8");
		Fs.writeFileSync(exclude, StringTools.rtrim(text) + "\nignored.txt\n");
		write(dir, "ignored.txt", "ignored content");
		write(dir, "normal.txt", "normal content");

		final patch = SnapshotRuntime.patch(dir, before);
		contains(patch, dir, "normal.txt", "snapshot info exclude normal file");
		missing(patch, dir, "ignored.txt", "snapshot info exclude ignored file");

		final after = SnapshotRuntime.trackDirectory(dir);
		final diffs = SnapshotRuntime.diffFull(dir, before, after);
		eq(hasDiff(diffs, "normal.txt"), true, "snapshot info exclude diffFull normal");
		eq(hasDiff(diffs, "ignored.txt"), false, "snapshot info exclude diffFull ignored");
		tmp.dispose();
	}

	static function gitInfoExcludeKeepsGlobalExcludes():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final global = NodePath.join(dir, "global.ignore");
		final config = NodePath.join(dir, "global.gitconfig");
		write(dir, "global.ignore", "global.tmp\n");
		write(dir, "global.gitconfig", "[core]\n\texcludesFile = " + global.split("\\").join("/") + "\n");

		final previous = NodeProcess.envValue("GIT_CONFIG_GLOBAL");
		NodeProcess.setEnv("GIT_CONFIG_GLOBAL", config);
		try {
			final before = SnapshotRuntime.trackDirectory(dir);
			final exclude = NodePath.join(dir, ".git/info/exclude");
			final text = Fs.readFileSync(exclude, "utf8");
			Fs.writeFileSync(exclude, StringTools.rtrim(text) + "\ninfo.tmp\n");

			write(dir, "global.tmp", "global content");
			write(dir, "info.tmp", "info content");
			write(dir, "normal.txt", "normal content");

			final patch = SnapshotRuntime.patch(dir, before);
			contains(patch, dir, "normal.txt", "snapshot global excludes normal file");
			missing(patch, dir, "global.tmp", "snapshot global excludes global file");
			missing(patch, dir, "info.tmp", "snapshot global excludes info file");

			final after = SnapshotRuntime.trackDirectory(dir);
			final diffs = SnapshotRuntime.diffFull(dir, before, after);
			eq(hasDiff(diffs, "normal.txt"), true, "snapshot global excludes diffFull normal");
			eq(hasDiff(diffs, "global.tmp"), false, "snapshot global excludes diffFull global");
			eq(hasDiff(diffs, "info.tmp"), false, "snapshot global excludes diffFull info");
			restoreEnv("GIT_CONFIG_GLOBAL", previous);
		} catch (error:haxe.Exception) {
			restoreEnv("GIT_CONFIG_GLOBAL", previous);
			tmp.dispose();
			throw error;
		}
		tmp.dispose();
	}

	static function projectStateIsolation():Void {
		final first = bootstrap();
		final second = bootstrap();
		final firstDir = first.path;
		final secondDir = second.path;

		final firstBefore = SnapshotRuntime.trackDirectory(firstDir);
		write(firstDir, "project1.txt", "project1 content");
		final firstPatch = SnapshotRuntime.patch(firstDir, firstBefore);
		contains(firstPatch, firstDir, "project1.txt", "snapshot first project file");
		missing(firstPatch, secondDir, "project2.txt", "snapshot first project excludes second project");

		final secondBefore = SnapshotRuntime.trackDirectory(secondDir);
		write(secondDir, "project2.txt", "project2 content");
		final secondPatch = SnapshotRuntime.patch(secondDir, secondBefore);
		contains(secondPatch, secondDir, "project2.txt", "snapshot second project file");
		missing(secondPatch, firstDir, "project1.txt", "snapshot second project excludes first project");

		first.dispose();
		second.dispose();
	}

	static function secondaryWorktreePatchDetection():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final worktree = dir + "-worktree";
		require(Git.run(dir, ["worktree", "add", worktree, "HEAD"]), "snapshot worktree add");
		try {
			eq(SnapshotRuntime.trackDirectory(dir) != "", true, "snapshot primary worktree track");
			final before = SnapshotRuntime.trackDirectory(worktree);
			write(worktree, "worktree.txt", "worktree content");
			final patch = SnapshotRuntime.patch(worktree, before);
			contains(patch, worktree, "worktree.txt", "snapshot secondary worktree patch file");
			cleanupWorktree(dir, worktree);
		} catch (error:haxe.Exception) {
			cleanupWorktree(dir, worktree);
			tmp.dispose();
			throw error;
		}
		tmp.dispose();
	}

	static function secondaryWorktreeRevertIsolation():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final worktree = dir + "-worktree";
		require(Git.run(dir, ["worktree", "add", worktree, "HEAD"]), "snapshot revert worktree add");
		try {
			eq(SnapshotRuntime.trackDirectory(dir) != "", true, "snapshot revert primary worktree track");
			write(dir, "worktree.txt", "primary content");

			final before = SnapshotRuntime.trackDirectory(worktree);
			write(worktree, "worktree.txt", "worktree content");
			final patch = SnapshotRuntime.patch(worktree, before);
			SnapshotRuntime.revert(worktree, [patch]);

			eq(Fs.existsSync(NodePath.join(worktree, "worktree.txt")), false, "snapshot worktree revert removes invoking file");
			eq(Fs.readFileSync(NodePath.join(dir, "worktree.txt"), "utf8"), "primary content", "snapshot worktree revert preserves primary file");
			cleanupWorktree(dir, worktree);
		} catch (error:haxe.Exception) {
			cleanupWorktree(dir, worktree);
			tmp.dispose();
			throw error;
		}
		tmp.dispose();
	}

	static function binaryDiffFull():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		writeBytes(dir, "binary.bin", [0x00, 0x01, 0x02, 0x03]);

		final after = SnapshotRuntime.trackDirectory(dir);
		final diffs = SnapshotRuntime.diffFull(dir, before, after);
		eq(diffs.length, 1, "snapshot binary diffFull count");
		final binaryDiff = diffs[0];
		eq(binaryDiff.file, "binary.bin", "snapshot binary diffFull file");
		eq(binaryDiff.patch, "", "snapshot binary diffFull empty patch");
		eq(binaryDiff.additions, 0, "snapshot binary diffFull additions");
		eq(binaryDiff.deletions, 0, "snapshot binary diffFull deletions");
		eq(binaryDiff.status, "added", "snapshot binary diffFull status");
		tmp.dispose();
	}

	static function binaryPatchAndRevert():Void {
		final added = bootstrap();
		final addedDir = added.path;
		final beforeAdd = SnapshotRuntime.trackDirectory(addedDir);
		writeBytes(addedDir, "image.png", [0x89, 0x50, 0x4e, 0x47]);
		final addedPatch = SnapshotRuntime.patch(addedDir, beforeAdd);
		contains(addedPatch, addedDir, "image.png", "snapshot binary added file");
		SnapshotRuntime.revert(addedDir, [addedPatch]);
		eq(Fs.existsSync(NodePath.join(addedDir, "image.png")), false, "snapshot revert added binary");
		added.dispose();

		final modified = bootstrap();
		final modifiedDir = modified.path;
		final original = [0x00, 0x01, 0x02, 0x03];
		writeBytes(modifiedDir, "data.bin", original);
		final beforeModify = SnapshotRuntime.trackDirectory(modifiedDir);
		writeBytes(modifiedDir, "data.bin", [0x04, 0x05, 0x06, 0x07]);
		final modifiedPatch = SnapshotRuntime.patch(modifiedDir, beforeModify);
		contains(modifiedPatch, modifiedDir, "data.bin", "snapshot binary modified file");
		SnapshotRuntime.revert(modifiedDir, [modifiedPatch]);
		eq(readBase64(modifiedDir, "data.bin"), bytesBase64(original), "snapshot revert modified binary bytes");
		modified.dispose();
	}

	static function symlinkPatch():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		final link = NodePath.join(dir, "link.txt");
		if (trySymlink(NodePath.join(dir, "a.txt"), link)) {
			final patch = SnapshotRuntime.patch(dir, before);
			contains(patch, dir, "link.txt", "snapshot symlink patch file");
		}
		tmp.dispose();
	}

	static function diffFullNoChanges():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final before = SnapshotRuntime.trackDirectory(dir);
		final after = SnapshotRuntime.trackDirectory(dir);
		final diffs = SnapshotRuntime.diffFull(dir, before, after);
		eq(diffs.length, 0, "snapshot diffFull no changes");
		tmp.dispose();
	}

	static function diffFullOrderAcrossBatchBoundaries():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		for (i in 0...140) {
			final id = pad3(i);
			write(dir, "order/" + id + ".txt", "before-" + id);
		}

		final before = SnapshotRuntime.trackDirectory(dir);
		for (i in 0...140) {
			final id = pad3(i);
			write(dir, "order/" + id + ".txt", "after-" + id);
		}

		final after = SnapshotRuntime.trackDirectory(dir);
		final diffs = SnapshotRuntime.diffFull(dir, before, after);
		eq(diffs.length, 140, "snapshot diffFull order count");
		for (i in 0...140)
			eq(diffs[i].file, "order/" + pad3(i) + ".txt", "snapshot diffFull order " + i);
		tmp.dispose();
	}

	static function diffFullStatuses():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		write(dir, "grow.txt", "one\n");
		write(dir, "trim.txt", "line1\nline2\n");
		write(dir, "delete.txt", "gone");
		final before = SnapshotRuntime.trackDirectory(dir);

		write(dir, "grow.txt", "one\ntwo\n");
		write(dir, "trim.txt", "line1\n");
		Fs.rmSync(NodePath.join(dir, "delete.txt"), {force: true});
		write(dir, "added.txt", "new");

		final after = SnapshotRuntime.trackDirectory(dir);
		final diffs = SnapshotRuntime.diffFull(dir, before, after);
		eq(diffs.length, 4, "snapshot diffFull status count");
		eq(statusOf(diffs, "added.txt"), "added", "snapshot diffFull added status");
		eq(statusOf(diffs, "delete.txt"), "deleted", "snapshot diffFull deleted status");
		eq(statusOf(diffs, "grow.txt"), "modified", "snapshot diffFull grow modified status");
		eq(statusOf(diffs, "trim.txt"), "modified", "snapshot diffFull trim modified status");
		tmp.dispose();
	}

	static function repeatedTrackStableHash():Void {
		final tmp = bootstrap();
		final dir = tmp.path;
		final first = SnapshotRuntime.trackDirectory(dir);
		final second = SnapshotRuntime.trackDirectory(dir);
		final third = SnapshotRuntime.trackDirectory(dir);
		eq(second, first, "snapshot repeated track second hash");
		eq(third, first, "snapshot repeated track third hash");
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

	static function hasDiff(diffs:Array<opencodehx.snapshot.SnapshotFileDiff>, file:String):Bool {
		for (diff in diffs) {
			if (diff.file == file)
				return true;
		}
		return false;
	}

	static function statusOf(diffs:Array<opencodehx.snapshot.SnapshotFileDiff>, file:String):String {
		for (diff in diffs) {
			if (diff.file == file)
				return diff.status;
		}
		throw 'missing snapshot diff for ${file}';
	}

	static function pad3(value:Int):String {
		return StringTools.lpad(Std.string(value), "0", 3);
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

	static function writeBytes(root:String, relative:String, bytes:Array<Int>):Void {
		final path = NodePath.join(root, relative);
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, Uint8Array.from(bytes));
	}

	static function readBase64(root:String, relative:String):String {
		return Fs.readFileBufferSync(NodePath.join(root, relative)).toString("base64");
	}

	static function bytesBase64(bytes:Array<Int>):String {
		return Buffer.from(Uint8Array.from(bytes)).toString("base64");
	}

	static function trySymlink(target:String, link:String):Bool {
		try {
			Fs.symlinkSync(target, link);
			return true;
		} catch (_:haxe.Exception) {
			return false;
		}
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

	static function restoreEnv(key:String, value:Null<String>):Void {
		if (value == null)
			NodeProcess.unsetEnv(key);
		else
			NodeProcess.setEnv(key, value);
	}

	static function cleanupWorktree(root:String, worktree:String):Void {
		Git.run(root, ["worktree", "remove", "--force", worktree]);
		Fs.rmSync(worktree, {recursive: true, force: true});
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
