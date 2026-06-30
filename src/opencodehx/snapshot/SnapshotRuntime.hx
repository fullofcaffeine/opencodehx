package opencodehx.snapshot;

import opencodehx.externs.node.Crypto;
import opencodehx.externs.node.Fs;
import opencodehx.git.Git;
import opencodehx.host.node.NodePath;
import opencodehx.project.InstanceRuntime.InstanceContext;
import opencodehx.project.InstanceRuntime.InstanceServiceID;

typedef SnapshotPatch = {
	final hash:String;
	final files:Array<String>;
}

private typedef SnapshotEntry = {
	final content:String;
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
						Fs.rmSync(absolute, {force: true});
				} else {
					writeFile(absolute, entry.content);
				}
			}
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
			final oldText = oldEntry == null ? "" : oldEntry.content;
			final newText = newEntry == null ? "" : newEntry.content;
			out.push({
				file: file,
				patch: "diff -- " + file,
				additions: lineCount(newText),
				deletions: lineCount(oldText),
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
			final stat = Fs.statSync(path);
			if (!stat.isFile())
				continue;
			final size = stat.size == null ? 0 : Std.int(stat.size);
			if (size > LIMIT)
				continue;
			entries.set(file, {
				content: Fs.readFileSync(path, "utf8"),
			});
		}
		return entries;
	}

	static function candidateFiles(directory:String):Array<String> {
		final result = Git.run(directory, ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "."]);
		if (result.code != 0)
			return [];
		final files = result.stdout.split(String.fromCharCode(0)).filter(item -> item != "");
		files.sort(Reflect.compare);
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
			if (next == null || previous == null || next.content != previous.content)
				out.push(file);
		}
		for (file in after.keys()) {
			if (seen.exists(file))
				continue;
			seen.set(file, true);
			out.push(file);
		}
		out.sort(Reflect.compare);
		return out;
	}

	static function ignored(directory:String, file:String):Bool {
		return Git.run(directory, ["check-ignore", "--no-index", "--quiet", "--", file]).code == 0;
	}

	static function hashSnapshot(entries:Map<String, SnapshotEntry>):String {
		final files:Array<String> = [];
		for (file in entries.keys())
			files.push(file);
		files.sort(Reflect.compare);
		final body:Array<String> = [];
		for (file in files) {
			final entry = entries.get(file);
			if (entry != null)
				body.push(file + "\u0000" + entry.content + "\u0000");
		}
		return Crypto.createHash("sha1").update(body.join("")).digest("hex");
	}

	static function relativeTo(directory:String, file:String):String {
		return NodePath.relative(NodePath.resolve(directory, ""), NodePath.resolve(file, "")).split("\\").join("/");
	}

	static function writeFile(path:String, content:String):Void {
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, content);
	}

	static function lineCount(text:String):Int {
		if (text == "")
			return 0;
		return text.split("\n").length;
	}

	static function hasSnapshotService(context:InstanceContext):Bool {
		for (service in context.services) {
			if (service.id == InstanceServiceID.Snapshot)
				return true;
		}
		return false;
	}
}
