package opencodehx.file;

class FileIgnore {
	static final FOLDERS = [
		"node_modules",
		"bower_components",
		".pnpm-store",
		"vendor",
		".npm",
		"dist",
		"build",
		"out",
		".next",
		"target",
		"bin",
		"obj",
		".git",
		".svn",
		".hg",
		".vscode",
		".idea",
		".turbo",
		".output",
		"desktop",
		".sst",
		".cache",
		".webkit-cache",
		"__pycache__",
		".pytest_cache",
		"mypy_cache",
		".history",
		".gradle",
	];

	static final FILES = [
		"**/*.swp",
		"**/*.swo",
		"**/*.pyc",
		"**/.DS_Store",
		"**/Thumbs.db",
		"**/logs/**",
		"**/tmp/**",
		"**/temp/**",
		"**/*.log",
		"**/coverage/**",
		"**/.nyc_output/**",
	];

	public static function match(filepath:String, ?options:{@:optional final extra:Array<String>; @:optional final whitelist:Array<String>;}):Bool {
		final normalized = normalize(filepath);
		final whitelist = options == null || options.whitelist == null ? [] : options.whitelist;
		for (pattern in whitelist) {
			if (glob(pattern, normalized))
				return false;
		}

		for (part in normalized.split("/")) {
			if (FOLDERS.indexOf(part) != -1)
				return true;
		}

		final extra = options == null || options.extra == null ? [] : options.extra;
		for (pattern in FILES.concat(extra)) {
			if (glob(pattern, normalized))
				return true;
		}
		return false;
	}

	public static function fromIgnoreText(text:String):Array<String> {
		final result:Array<String> = [];
		for (line in text.split("\n")) {
			final trimmed = StringTools.trim(line);
			if (trimmed == "" || StringTools.startsWith(trimmed, "#"))
				continue;
			if (StringTools.startsWith(trimmed, "!"))
				continue;
			result.push(trimmed);
		}
		return result;
	}

	public static function glob(pattern:String, filepath:String):Bool {
		final normalizedPattern = normalize(pattern);
		final normalizedFile = normalize(filepath);
		if (normalizedPattern == normalizedFile)
			return true;
		if (StringTools.endsWith(normalizedPattern, "/")) {
			return normalizedFile == normalizedPattern.substr(0, normalizedPattern.length - 1)
				|| StringTools.startsWith(normalizedFile, normalizedPattern);
		}
		if (normalizedPattern.indexOf("*") == -1) {
			return normalizedFile == normalizedPattern || StringTools.startsWith(normalizedFile, normalizedPattern + "/");
		}
		final regex = new EReg("^" + escapeGlob(normalizedPattern) + "$", "");
		return regex.match(normalizedFile);
	}

	static function escapeGlob(pattern:String):String {
		var out = "";
		var index = 0;
		while (index < pattern.length) {
			final ch = pattern.charAt(index);
			if (ch == "*" && pattern.charAt(index + 1) == "*") {
				out += ".*";
				index += 2;
				continue;
			}
			if (ch == "*") {
				out += "[^/]*";
			} else if ("\\.^$+?()[]{}|".indexOf(ch) != -1) {
				out += "\\" + ch;
			} else {
				out += ch;
			}
			index++;
		}
		return out;
	}

	static function normalize(path:String):String {
		return StringTools.replace(path, "\\", "/");
	}
}
