package opencodehx.snapshot;

using StringTools;

import opencodehx.externs.node.Crypto;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Buffer;
import opencodehx.git.Git;
import opencodehx.host.node.NodePath;
import opencodehx.project.InstanceRuntime.InstanceContext;
import opencodehx.project.InstanceRuntime.InstanceServiceID;
import opencodehx.util.Compare.compareString;

typedef SnapshotPatch = {
	final hash:String;
	final files:Array<String>;
}

private typedef SnapshotEntry = {
	final content:String;
	final binary:Bool;
	final kind:SnapshotEntryKind;
}

private enum SnapshotEntryKind {
	File;
	Symlink;
}

/**
 * Focused snapshot runtime for OpenCode's Git-backed file-state behavior.
 *
 * Upstream stores snapshots in a separate Git index. This first Haxe slice uses
 * Git for candidate discovery and ignore semantics, then keeps process-local
 * typed content snapshots for patch/revert/diff smoke evidence. The API is
 * intentionally small until the full Effect service and persistent Git-dir
 * lifecycle are ported.
 */
class SnapshotRuntime {
	static inline final LIMIT = 2 * 1024 * 1024;
	static final snapshots:Map<String, Map<String, SnapshotEntry>> = new Map();

	public static function track(context:InstanceContext):String {
		if (!hasSnapshotService(context))
			throw "Snapshot service is not attached to this instance";
		return trackDirectory(context.directory);
	}

	public static function trackDirectory(directory:String):String {
		final entries = readCurrent(directory);
		final hash = hashSnapshot(entries);
		snapshots.set(hash, entries);
		return hash;
	}

	public static function patch(directory:String, hash:String):SnapshotPatch {
		final before = snapshots.get(hash);
		if (before == null)
			return {hash: hash, files: []};
		final current = readCurrent(directory);
		final files:Array<String> = [];
		for (file in changedFiles(before, current)) {
			if (!ignored(directory, file))
				files.push(NodePath.resolve(NodePath.join(directory, file), "").split("\\").join("/"));
		}
		return {hash: hash, files: files};
	}

	public static function revert(directory:String, patches:Array<SnapshotPatch>):Void {
		final seen:Map<String, Bool> = new Map();
		for (item in patches) {
			final snapshot = snapshots.get(item.hash);
			for (file in item.files) {
				final absolute = NodePath.resolve(file, "");
				if (seen.exists(absolute))
					continue;
				seen.set(absolute, true);
				final relative = relativeTo(directory, absolute);
				final entry = snapshot == null ? null : snapshot.get(relative);
				if (entry == null) {
					if (Fs.existsSync(absolute))
						Fs.rmSync(absolute, {force: true, recursive: true});
				} else {
					writeFile(absolute, entry);
				}
			}
		}
	}

	public static function restore(directory:String, hash:String):Void {
		final snapshot = snapshots.get(hash);
		if (snapshot == null)
			return;
		final files:Array<String> = [];
		for (file in snapshot.keys())
			files.push(file);
		files.sort(compareString);
		for (file in files) {
			final entry = snapshot.get(file);
			if (entry != null)
				writeFile(NodePath.join(directory, file), entry);
		}
	}

	public static function diff(directory:String, hash:String):String {
		final patchInfo = patch(directory, hash);
		if (patchInfo.files.length == 0)
			return "";
		return [for (file in patchInfo.files) "diff -- " + relativeTo(directory, file)].join("\n");
	}

	public static function diffFull(directory:String, from:String, to:String):Array<SnapshotFileDiff> {
		final before = snapshots.get(from);
		final after = snapshots.get(to);
		if (before == null || after == null)
			return [];
		final out:Array<SnapshotFileDiff> = [];
		for (file in changedFiles(before, after)) {
			final oldEntry = before.get(file);
			final newEntry = after.get(file);
			final binary = isBinaryDiff(oldEntry, newEntry);
			final oldText = oldEntry == null || oldEntry.binary ? "" : oldEntry.content;
			final newText = newEntry == null || newEntry.binary ? "" : newEntry.content;
			out.push({
				file: file,
				patch: binary ? "" : textPatch(file, oldText, newText),
				additions: binary ? 0 : lineCount(newText),
				deletions: binary ? 0 : lineCount(oldText),
				status: oldEntry == null ? "added" : (newEntry == null ? "deleted" : "modified"),
			});
		}
		return out;
	}

	public static function reset():Void {
		snapshots.clear();
	}

	static function readCurrent(directory:String):Map<String, SnapshotEntry> {
		final entries:Map<String, SnapshotEntry> = new Map();
		for (file in candidateFiles(directory)) {
			final path = NodePath.join(directory, file);
			if (!Fs.existsSync(path))
				continue;
			final stat = Fs.lstatSync(path);
			if (stat.isSymbolicLink()) {
				entries.set(file, {
					content: Fs.readlinkSync(path),
					binary: false,
					kind: Symlink,
				});
				continue;
			}
			if (!stat.isFile())
				continue;
			final size = stat.size == null ? 0 : Std.int(stat.size);
			if (size > LIMIT)
				continue;
			final buffer = Fs.readFileBufferSync(path);
			final text = buffer.toString("utf8");
			final binary = isBinaryPath(file) || text.indexOf(String.fromCharCode(0)) != -1;
			entries.set(file, {
				content: binary ? buffer.toString("base64") : text,
				binary: binary,
				kind: File,
			});
		}
		return entries;
	}

	static function candidateFiles(directory:String):Array<String> {
		final result = Git.run(directory, ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "."]);
		if (result.code != 0)
			return [];
		final files = result.stdout.split(String.fromCharCode(0)).filter(item -> item != "");
		files.sort(compareString);
		return files;
	}

	static function changedFiles(before:Map<String, SnapshotEntry>, after:Map<String, SnapshotEntry>):Array<String> {
		final seen:Map<String, Bool> = new Map();
		final out:Array<String> = [];
		for (file in before.keys()) {
			if (seen.exists(file))
				continue;
			seen.set(file, true);
			final next = after.get(file);
			final previous = before.get(file);
			if (entryChanged(previous, next))
				out.push(file);
		}
		for (file in after.keys()) {
			if (seen.exists(file))
				continue;
			seen.set(file, true);
			out.push(file);
		}
		out.sort(compareString);
		return out;
	}

	static function ignored(directory:String, file:String):Bool {
		return Git.run(directory, ["check-ignore", "--no-index", "--quiet", "--", file]).code == 0;
	}

	static function hashSnapshot(entries:Map<String, SnapshotEntry>):String {
		final files:Array<String> = [];
		for (file in entries.keys())
			files.push(file);
		files.sort(compareString);
		final body:Array<String> = [];
		for (file in files) {
			final entry = entries.get(file);
			if (entry != null)
				body.push(file
					+ "\u0000"
					+ entryKindName(entry.kind)
					+ "\u0000"
					+ (entry.binary ? "binary" : "text")
					+ "\u0000"
					+ entry.content
					+ "\u0000");
		}
		return Crypto.createHash("sha1").update(body.join("")).digest("hex");
	}

	static function relativeTo(directory:String, file:String):String {
		return NodePath.relative(NodePath.resolve(directory, ""), NodePath.resolve(file, "")).split("\\").join("/");
	}

	static function writeFile(path:String, entry:SnapshotEntry):Void {
		ensureDirectory(NodePath.dirname(path));
		if (entry.kind == Symlink) {
			if (Fs.existsSync(path))
				Fs.rmSync(path, {force: true, recursive: true});
			Fs.symlinkSync(entry.content, path);
			return;
		}
		if (Fs.existsSync(path) && Fs.statSync(path).isDirectory())
			Fs.rmSync(path, {force: true, recursive: true});
		if (entry.binary)
			Fs.writeFileSync(path, Buffer.from(entry.content, "base64"));
		else
			Fs.writeFileSync(path, entry.content);
	}

	static function ensureDirectory(path:String):Void {
		if (Fs.existsSync(path)) {
			if (Fs.statSync(path).isDirectory())
				return;
			Fs.rmSync(path, {force: true});
		}
		ensureDirectory(NodePath.dirname(path));
		Fs.mkdirSync(path);
	}

	static function lineCount(text:String):Int {
		if (text == "")
			return 0;
		return text.split("\n").length;
	}

	static function textPatch(file:String, oldText:String, newText:String):String {
		final lines = ["diff -- " + file];
		for (line in patchLines("-", oldText))
			lines.push(line);
		for (line in patchLines("+", newText))
			lines.push(line);
		return lines.join("\n");
	}

	static function patchLines(prefix:String, text:String):Array<String> {
		if (text == "")
			return [];
		return [for (line in text.split("\n")) prefix + line];
	}

	static function entryChanged(previous:Null<SnapshotEntry>, next:Null<SnapshotEntry>):Bool {
		return next == null || previous == null || next.kind != previous.kind || next.binary != previous.binary || next.content != previous.content;
	}

	static function isBinaryDiff(oldEntry:Null<SnapshotEntry>, newEntry:Null<SnapshotEntry>):Bool {
		return (oldEntry != null && oldEntry.binary) || (newEntry != null && newEntry.binary);
	}

	static function entryKindName(kind:SnapshotEntryKind):String {
		return switch kind {
			case File: "file";
			case Symlink: "symlink";
		}
	}

	static function isBinaryPath(file:String):Bool {
		final normalized = file.toLowerCase();
		return normalized.endsWith(".bin") || normalized.endsWith(".png") || normalized.endsWith(".jpg") || normalized.endsWith(".jpeg")
			|| normalized.endsWith(".gif") || normalized.endsWith(".webp") || normalized.endsWith(".pdf") || normalized.endsWith(".wasm")
			|| normalized.endsWith(".zip") || normalized.endsWith(".gz");
	}

	static function hasSnapshotService(context:InstanceContext):Bool {
		for (service in context.services) {
			if (service.id == InstanceServiceID.Snapshot)
				return true;
		}
		return false;
	}
}
