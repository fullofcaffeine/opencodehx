package opencodehx.util;

import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.util.Compare.compareString;

typedef GlobOptions = {
	@:optional final cwd:String;
	@:optional final absolute:Bool;
	@:optional final include:String;
	@:optional final dot:Bool;
	@:optional final symlink:Bool;
}

class GlobRuntime {
	public static function scan(pattern:String, ?options:GlobOptions):Promise<Array<String>> {
		return Promise.resolve(scanSync(pattern, options));
	}

	public static function scanSync(pattern:String, ?options:GlobOptions):Array<String> {
		final cwd = options != null && options.cwd != null ? options.cwd : ".";
		final out:Array<String> = [];
		final entries = walk(cwd, options != null && options.symlink == true, []);
		for (entry in entries) {
			if (options == null || options.include != "all") {
				if (entry.kind != File)
					continue;
			}
			final relative = normalize(NodePath.relative(cwd, entry.path));
			if (relative == "")
				continue;
			if (!(options != null && options.dot == true) && hasHiddenSegment(relative))
				continue;
			if (match(pattern, relative))
				out.push(options != null && options.absolute == true ? entry.path : relative);
		}
		out.sort(compareString);
		return out;
	}

	public static function match(pattern:String, filepath:String):Bool {
		final normalized = normalize(filepath);
		for (expanded in expandBraces(normalize(pattern))) {
			if (globRegex(expanded).match(normalized))
				return true;
		}
		return false;
	}

	static function walk(root:String, followSymlinks:Bool, seen:Array<String>):Array<GlobEntry> {
		var out:Array<GlobEntry> = [];
		if (!Fs.existsSync(root))
			return out;
		for (entry in Fs.readdirDirentsSync(root, {withFileTypes: true})) {
			final name = entry.name;
			final absolute = NodePath.join(root, name);
			final isDirectory = entry.isDirectory();
			final isFile = entry.isFile();
			final isSymlink = entry.isSymbolicLink();
			if (isDirectory) {
				out.push({path: absolute, kind: Directory});
				out = out.concat(walk(absolute, followSymlinks, seen));
			} else if (isFile) {
				out.push({path: absolute, kind: File});
			} else if (isSymlink && followSymlinks) {
				try {
					final stat = Fs.statSync(absolute);
					if (stat.isDirectory()) {
						out.push({path: absolute, kind: Directory});
						final real = Fs.realpathSync(absolute);
						if (seen.indexOf(real) == -1) {
							seen.push(real);
							out = out.concat(walk(absolute, followSymlinks, seen));
						}
					} else if (stat.isFile()) {
						out.push({path: absolute, kind: File});
					}
				} catch (_:Dynamic) {}
			}
		}
		return out;
	}

	static function expandBraces(pattern:String):Array<String> {
		final open = pattern.indexOf("{");
		if (open == -1)
			return [pattern];
		final close = pattern.indexOf("}", open + 1);
		if (close == -1)
			return [pattern];
		final prefix = pattern.substr(0, open);
		final suffix = pattern.substr(close + 1);
		final choices = pattern.substr(open + 1, close - open - 1).split(",");
		final out:Array<String> = [];
		for (choice in choices) {
			for (expanded in expandBraces(prefix + choice + suffix))
				out.push(expanded);
		}
		return out;
	}

	static function globRegex(pattern:String):EReg {
		var out = "^";
		var index = 0;
		while (index < pattern.length) {
			final ch = pattern.charAt(index);
			if (ch == "*" && pattern.charAt(index + 1) == "*") {
				final slash = pattern.charAt(index + 2) == "/";
				out += slash ? "(?:.*/)?" : ".*";
				index += slash ? 3 : 2;
				continue;
			}
			if (ch == "*") {
				out += "[^/]*";
			} else if (ch == "?") {
				out += "[^/]";
			} else if ("\\.^$+()[]{}|".indexOf(ch) != -1) {
				out += "\\" + ch;
			} else {
				out += ch;
			}
			index++;
		}
		return new EReg(out + "$", "");
	}

	static function hasHiddenSegment(path:String):Bool {
		for (segment in path.split("/")) {
			if (StringTools.startsWith(segment, "."))
				return true;
		}
		return false;
	}

	static function normalize(path:String):String {
		return StringTools.replace(path, "\\", "/");
	}
}

private typedef GlobEntry = {
	final path:String;
	final kind:GlobEntryKind;
}

private enum GlobEntryKind {
	File;
	Directory;
}
