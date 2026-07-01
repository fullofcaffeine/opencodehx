package opencodehx.smoke;

import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.patch.PatchRuntime;
import opencodehx.patch.PatchRuntime.MaybeApplyPatch;
import opencodehx.patch.PatchRuntime.MaybeApplyPatchVerified;
import opencodehx.patch.PatchRuntime.PatchFileChange;
import opencodehx.patch.PatchRuntime.PatchHunk;
import opencodehx.smoke.SmokeCleanup.withCleanup;

class PatchSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-patch-"));
		withCleanup(() -> {
			parsePatch();
			maybeParseApplyPatch();
			applyPatch(root);
			verifiedPlanning(root);
			errorHandling(root);
		}, () -> Fs.rmSync(root, {recursive: true, force: true}));
	}

	static function parsePatch():Void {
		final add = PatchRuntime.parsePatch(["*** Begin Patch", "*** Add File: test.txt", "+Hello World", "*** End Patch"].join("\n"));
		eq(add.hunks.length, 1, "parse add hunk count");
		switch add.hunks[0] {
			case AddFile(path, contents):
				eq(path, "test.txt", "parse add path");
				eq(contents, "Hello World", "parse add contents");
			case _:
				throw "parse add hunk type";
		}

		final mixed = PatchRuntime.parsePatch([
			"*** Begin Patch",
			"*** Add File: new.txt",
			"+This is a new file",
			"*** Update File: existing.txt",
			"@@",
			" old line",
			"-new line",
			"+updated line",
			"*** End Patch"
		].join("\n"));
		eq(mixed.hunks.length, 2, "parse multiple hunk count");
		eq(hunkKind(mixed.hunks[0]), "add", "parse multiple first kind");
		eq(hunkKind(mixed.hunks[1]), "update", "parse multiple second kind");

		final moved = PatchRuntime.parsePatch([
			"*** Begin Patch",
			"*** Update File: old-name.txt",
			"*** Move to: new-name.txt",
			"@@",
			"-Old content",
			"+New content",
			"*** End Patch"
		].join("\n"));
		switch moved.hunks[0] {
			case UpdateFile(path, movePath, _):
				eq(path, "old-name.txt", "parse move source");
				eq(movePath, "new-name.txt", "parse move target");
			case _:
				throw "parse move hunk type";
		}

		expectPatchFailure(() -> PatchRuntime.parsePatch("This is not a valid patch"), "Invalid patch format", "parse invalid format");
	}

	static function maybeParseApplyPatch():Void {
		final patchText = ["*** Begin Patch", "*** Add File: test.txt", "+Content", "*** End Patch"].join("\n");

		switch PatchRuntime.maybeParseApplyPatch(["apply_patch", patchText]) {
			case Body(args):
				eq(args.patch, patchText, "maybe direct patch body");
				eq(args.hunks.length, 1, "maybe direct hunk count");
			case _:
				throw "maybe direct expected body";
		}

		switch PatchRuntime.maybeParseApplyPatch(["applypatch", patchText]) {
			case Body(_):
			case _:
				throw "maybe applypatch expected body";
		}

		final script = [
			"apply_patch <<'PATCH'",
			"*** Begin Patch",
			"*** Add File: test.txt",
			"+Content",
			"*** End Patch",
			"PATCH"
		].join("\n");
		switch PatchRuntime.maybeParseApplyPatch(["bash", "-lc", script]) {
			case Body(args):
				eq(args.hunks.length, 1, "maybe heredoc hunk count");
			case _:
				throw "maybe heredoc expected body";
		}

		switch PatchRuntime.maybeParseApplyPatch(["echo", "hello"]) {
			case NotApplyPatch:
			case _:
				throw "maybe non patch expected not apply patch";
		}
	}

	static function applyPatch(root:String):Void {
		final newFile = NodePath.join(root, "new-file.txt");
		final add = PatchRuntime.applyPatch([
			"*** Begin Patch",
			'*** Add File: ${newFile}',
			"+Hello World",
			"+This is a new file",
			"*** End Patch"
		].join("\n"));
		eq(add.added.length, 1, "apply add count");
		eq(add.modified.length, 0, "apply add modified count");
		eq(add.deleted.length, 0, "apply add deleted count");
		eq(Fs.readFileSync(add.added[0], "utf8"), "Hello World\nThis is a new file", "apply add contents");

		final deleteFile = NodePath.join(root, "to-delete.txt");
		Fs.writeFileSync(deleteFile, "This file will be deleted", "utf8");
		final deleted = PatchRuntime.applyPatch(["*** Begin Patch", '*** Delete File: ${deleteFile}', "*** End Patch"].join("\n"));
		eq(deleted.deleted[0], deleteFile, "apply delete path");
		eq(Fs.existsSync(deleteFile), false, "apply delete removes file");

		final updateFile = NodePath.join(root, "to-update.txt");
		Fs.writeFileSync(updateFile, "line 1\nline 2\nline 3\n", "utf8");
		final updated = PatchRuntime.applyPatch([
			"*** Begin Patch",
			'*** Update File: ${updateFile}',
			"@@",
			" line 1",
			"-line 2",
			"+line 2 updated",
			" line 3",
			"*** End Patch"
		].join("\n"));
		eq(updated.modified[0], updateFile, "apply update path");
		eq(Fs.readFileSync(updateFile, "utf8"), "line 1\nline 2 updated\nline 3\n", "apply update contents");

		final bom = String.fromCharCode(0xfeff);
		final bomFile = NodePath.join(root, "patch-bom.cs");
		Fs.writeFileSync(bomFile, bom + "using System;\n\nclass Test {}\n", "utf8");
		final bomUpdate = PatchRuntime.deriveNewContentsFromChunks(bomFile, [
			{
				oldLines: ["class Test {}"],
				newLines: ["class Test {}", "class Next {}"]
			}
		]);
		eq(bomUpdate.bom, true, "apply update records BOM");
		eq(bomUpdate.unifiedDiff.indexOf(bom), -1, "apply update diff hides BOM");
		PatchRuntime.applyPatch([
			"*** Begin Patch",
			'*** Update File: ${bomFile}',
			"@@",
			" class Test {}",
			"+class Next {}",
			"*** End Patch"
		].join("\n"));
		final bomContent = Fs.readFileSync(bomFile, "utf8");
		eq(bomContent.charCodeAt(0), 0xfeff, "apply update preserves BOM");
		eq(bomContent.substr(1), "using System;\n\nclass Test {}\nclass Next {}\n", "apply update changes visible BOM content");

		final oldPath = NodePath.join(root, "old-name.txt");
		final newPath = NodePath.join(root, "new-name.txt");
		Fs.writeFileSync(oldPath, "old content\n", "utf8");
		final moved = PatchRuntime.applyPatch([
			"*** Begin Patch",
			'*** Update File: ${oldPath}',
			'*** Move to: ${newPath}',
			"@@",
			"-old content",
			"+new content",
			"*** End Patch"
		].join("\n"));
		eq(moved.modified[0], newPath, "apply move target");
		eq(Fs.existsSync(oldPath), false, "apply move removes source");
		eq(Fs.readFileSync(newPath, "utf8"), "new content\n", "apply move contents");

		final nested = NodePath.join(NodePath.join(NodePath.join(root, "deep"), "nested"), "file.txt");
		final nestedAdd = PatchRuntime.applyPatch([
			"*** Begin Patch",
			'*** Add File: ${nested}',
			"+Deep nested content",
			"*** End Patch"
		].join("\n"));
		eq(nestedAdd.added[0], nested, "apply nested add path");
		eq(Fs.existsSync(nested), true, "apply nested parent directories");

		final emptyFile = NodePath.join(root, "empty.txt");
		Fs.writeFileSync(emptyFile, "", "utf8");
		PatchRuntime.applyPatch([
			"*** Begin Patch",
			'*** Update File: ${emptyFile}',
			"@@",
			"+First line",
			"*** End Patch"
		].join("\n"));
		eq(Fs.readFileSync(emptyFile, "utf8"), "First line\n", "apply empty file");

		final noNewline = NodePath.join(root, "no-newline.txt");
		Fs.writeFileSync(noNewline, "no newline", "utf8");
		PatchRuntime.applyPatch([
			"*** Begin Patch",
			'*** Update File: ${noNewline}',
			"@@",
			"-no newline",
			"+has newline now",
			"*** End Patch"
		].join("\n"));
		eq(Fs.readFileSync(noNewline, "utf8"), "has newline now\n", "apply no trailing newline");

		final multi = NodePath.join(root, "multi-chunk.txt");
		Fs.writeFileSync(multi, "line 1\nline 2\nline 3\nline 4\n", "utf8");
		PatchRuntime.applyPatch([
			"*** Begin Patch",
			'*** Update File: ${multi}',
			"@@",
			" line 1",
			"-line 2",
			"+LINE 2",
			"@@",
			" line 3",
			"-line 4",
			"+LINE 4",
			"*** End Patch"
		].join("\n"));
		eq(Fs.readFileSync(multi, "utf8"), "line 1\nLINE 2\nline 3\nLINE 4\n", "apply multiple update chunks");
	}

	static function verifiedPlanning(root:String):Void {
		final file = NodePath.join(root, "verified.txt");
		Fs.writeFileSync(file, "before\n", "utf8");
		final patchText = [
			"*** Begin Patch",
			'*** Update File: ${file}',
			"@@",
			"-before",
			"+after",
			"*** End Patch"
		].join("\n");

		switch PatchRuntime.maybeParseApplyPatchVerified(["apply_patch", patchText], root) {
			case Body(action):
				eq(action.cwd, root, "verified cwd");
				eq(action.patch, patchText, "verified patch source");
				eq(action.changes.length, 1, "verified change count");
				eq(action.changes[0].path, file, "verified change path");
				switch action.changes[0].change {
					case UpdateChange(diff, movePath, newContent):
						eq(movePath, null, "verified update no move");
						eq(newContent, "after\n", "verified new content");
						eq(diff.indexOf("+after") != -1, true, "verified diff");
					case _:
						throw "verified expected update change";
				}
			case _:
				throw "verified expected body";
		}

		switch PatchRuntime.maybeParseApplyPatchVerified([patchText], root) {
			case CorrectnessError(message):
				eq(message, "ImplicitInvocation", "verified implicit invocation rejection");
			case _:
				throw "verified implicit invocation expected correctness error";
		}
	}

	static function errorHandling(root:String):Void {
		final missing = NodePath.join(root, "does-not-exist.txt");
		expectPatchFailure(() -> PatchRuntime.applyPatch([
			"*** Begin Patch",
			'*** Update File: ${missing}',
			"@@",
			"-old line",
			"+new line",
			"*** End Patch"
		].join("\n")), "Failed to read file", "apply update missing file");

		expectPatchFailure(() -> PatchRuntime.applyPatch(["*** Begin Patch", '*** Delete File: ${missing}', "*** End Patch"].join("\n")), "",
			"apply delete missing file");
	}

	static function hunkKind(hunk:PatchHunk):String {
		return switch hunk {
			case AddFile(_, _): "add";
			case DeleteFile(_): "delete";
			case UpdateFile(_, _, _): "update";
		}
	}

	static function expectPatchFailure(run:() -> Void, containsText:String, label:String):Void {
		try {
			run();
		} catch (error:haxe.Exception) {
			if (containsText == "" || error.message.indexOf(containsText) != -1)
				return;
			throw '${label}: unexpected failure ${error.message}';
		} catch (error:Dynamic) {
			// Host filesystem failures may not share haxe.Exception; this smoke
			// keeps that boundary local while checking the user-facing message.
			if (containsText == "" || Std.string(error).indexOf(containsText) != -1)
				return;
			throw '${label}: unexpected failure ${Std.string(error)}';
		}
		throw '${label}: expected failure';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
