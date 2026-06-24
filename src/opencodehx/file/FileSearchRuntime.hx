package opencodehx.file;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;

enum abstract FileSearchType(String) from String to String {
	var File = "file";
	var Directory = "directory";
}

typedef FileSearchInput = {
	final query:String;
	@:optional final limit:Int;
	@:optional final type:FileSearchType;
}

class FileSearchRuntime {
	public static function search(root:String, input:FileSearchInput):Array<String> {
		final entries:Array<FileSearchEntry> = [];
		collect(NodePath.resolve(root, "."), NodePath.resolve(root, "."), entries);

		final query = input.query.toLowerCase();
		final wantsHidden = StringTools.startsWith(query, ".");
		final filtered:Array<FileSearchEntry> = [];
		for (entry in entries) {
			if (!matchesType(entry, input.type))
				continue;
			if (query != "" && !matchesQuery(entry, query))
				continue;
			filtered.push(entry);
		}
		filtered.sort((a, b) -> compareSearch(a, b, wantsHidden));

		final result:Array<String> = [];
		for (entry in filtered) {
			if (input.limit != null && result.length >= input.limit)
				break;
			result.push(entry.path);
		}
		return result;
	}

	static function collect(root:String, current:String, entries:Array<FileSearchEntry>):Void {
		for (entry in Fs.readdirSync(current, {withFileTypes: true})) {
			final name = Std.string(Reflect.field(entry, "name"));
			if (name == ".git" || name == ".DS_Store")
				continue;
			final absolute = NodePath.join(current, name);
			final isDirectory:Bool = Reflect.callMethod(entry, Reflect.field(entry, "isDirectory"), []);
			final relative = normalize(NodePath.relative(root, absolute));
			final path = isDirectory ? relative + "/" : relative;
			entries.push({
				path: path,
				name: name,
				isDirectory: isDirectory,
				hidden: hasHiddenSegment(path),
			});
			if (isDirectory)
				collect(root, absolute, entries);
		}
	}

	static function matchesType(entry:FileSearchEntry, type:Null<FileSearchType>):Bool {
		if (type == null)
			return !entry.isDirectory;
		return type == Directory ? entry.isDirectory : !entry.isDirectory;
	}

	static function matchesQuery(entry:FileSearchEntry, query:String):Bool {
		final path = entry.path.toLowerCase();
		final name = entry.name.toLowerCase();
		return path.indexOf(query) != -1 || name.indexOf(query) != -1 || isSubsequence(query, path);
	}

	static function compareSearch(a:FileSearchEntry, b:FileSearchEntry, hiddenFirst:Bool):Int {
		if (a.hidden != b.hidden)
			return hiddenFirst ? (a.hidden ? -1 : 1) : (a.hidden ? 1 : -1);
		return Reflect.compare(a.path, b.path);
	}

	static function hasHiddenSegment(path:String):Bool {
		for (part in path.split("/")) {
			if (part.length > 1 && StringTools.startsWith(part, "."))
				return true;
		}
		return false;
	}

	static function isSubsequence(query:String, text:String):Bool {
		var index = 0;
		for (i in 0...text.length) {
			if (index < query.length && text.charAt(i) == query.charAt(index))
				index++;
		}
		return index == query.length;
	}

	static function normalize(path:String):String {
		return StringTools.replace(path, "\\", "/");
	}
}

typedef FileSearchEntry = {
	final path:String;
	final name:String;
	final isDirectory:Bool;
	final hidden:Bool;
}
