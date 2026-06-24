package opencodehx.file;

import opencodehx.externs.node.Fs;
import opencodehx.file.Ripgrep.SearchResult;
import opencodehx.git.Git;
import opencodehx.host.node.NodePath;

typedef FileNode = {
	final name:String;
	final path:String;
	final absolute:String;
	final type:String;
	final ignored:Bool;
}

typedef FileReadResult = {
	final type:String;
	final content:String;
	@:optional final diff:String;
	@:optional final patch:FilePatch;
	@:optional final encoding:String;
	@:optional final mimeType:String;
}

typedef FilePatch = {
	final oldFileName:String;
	final newFileName:String;
	@:optional final oldHeader:String;
	@:optional final newHeader:String;
	final hunks:Array<FilePatchHunk>;
	@:optional final index:String;
}

typedef FilePatchHunk = {
	final oldStart:Int;
	final oldLines:Int;
	final newStart:Int;
	final newLines:Int;
	final lines:Array<String>;
}

class FileSystem {
	static final TEXT_EXTENSIONS = [
		"ts", "tsx", "js", "jsx", "mts", "cts", "mjs", "cjs", "json", "jsonc", "md", "txt", "sh", "bash", "zsh", "fish", "py", "rb", "go", "rs", "java", "c",
		"cpp", "h", "hpp", "css", "scss", "html", "xml", "yaml", "yml", "toml", "env", "cfg", "conf"
	];
	static final TEXT_NAMES = [
		"dockerfile",
		"makefile",
		".gitignore",
		".gitattributes",
		".editorconfig",
		".npmrc",
		".nvmrc",
		".prettierrc",
		".eslintrc"
	];
	static final BINARY_EXTENSIONS = ["bin", "so", "dylib", "dll", "exe", "class", "jar", "zip", "gz", "tar", "pdf"];
	static final IMAGE_MIME = [
		"png" => "image/png",
		"jpg" => "image/jpeg",
		"jpeg" => "image/jpeg",
		"gif" => "image/gif",
		"webp" => "image/webp",
		"bmp" => "image/bmp",
		"ico" => "image/x-icon",
		"svg" => "image/svg+xml",
		"svgz" => "image/svg+xml",
	];

	public static function contains(root:String, target:String):Bool {
		final relative = normalize(NodePath.relative(NodePath.resolve(root, "."), NodePath.resolve(target, ".")));
		return relative == "" || (!StringTools.startsWith(relative, "..") && !NodePath.isAbsolute(relative));
	}

	public static function read(root:String, file:String):FileReadResult {
		final absolute = resolveInside(root, file);
		if (isImageByExtension(file)) {
			if (!Fs.existsSync(absolute) || !Fs.statSync(absolute).isFile())
				return {type: "text", content: ""};
			return {
				type: "text",
				content: Fs.readFileBufferSync(absolute).toString("base64"),
				mimeType: imageMime(file),
				encoding: "base64",
			};
		}
		final knownText = isTextByExtension(file) || isTextByName(file);
		if (isBinaryByExtension(file) && !knownText)
			return {type: "binary", content: ""};
		if (!Fs.existsSync(absolute) || !Fs.statSync(absolute).isFile())
			return {type: "text", content: ""};
		return textRead(root, file, StringTools.trim(Fs.readFileSync(absolute, "utf8")));
	}

	public static function readText(root:String, file:String):String {
		final absolute = resolveInside(root, file);
		if (!Fs.existsSync(absolute) || !Fs.statSync(absolute).isFile())
			throw 'No such file: ${file}';
		return Fs.readFileSync(absolute, "utf8");
	}

	public static function list(root:String, ?dir:String):Array<FileNode> {
		final base = dir == null || dir == "" ? root : resolveInside(root, dir);
		final patterns = loadIgnore(root);
		final entries = Fs.readdirSync(base, {withFileTypes: true});
		final nodes:Array<FileNode> = [];
		for (entry in entries) {
			final name = Std.string(Reflect.field(entry, "name"));
			if (name == ".git" || name == ".DS_Store")
				continue;
			final absolute = NodePath.join(base, name);
			final relative = normalize(NodePath.relative(root, absolute));
			final isDirectory:Bool = Reflect.callMethod(entry, Reflect.field(entry, "isDirectory"), []);
			final type = isDirectory ? "directory" : "file";
			nodes.push({
				name: name,
				path: relative,
				absolute: absolute,
				type: type,
				ignored: FileIgnore.match(isDirectory ? relative + "/" : relative, {extra: patterns}),
			});
		}
		nodes.sort(compareNode);
		return nodes;
	}

	public static function files(root:String, ?glob:Array<String>, ?hidden:Bool):Array<String> {
		return Ripgrep.files({cwd: root, glob: glob, hidden: hidden});
	}

	public static function search(root:String, pattern:String, ?glob:Array<String>, ?limit:Int):SearchResult {
		return Ripgrep.search({
			cwd: root,
			pattern: pattern,
			glob: glob,
			limit: limit
		});
	}

	public static function resolveInside(root:String, file:String):String {
		final absolute = NodePath.resolve(root, file);
		if (!contains(root, absolute))
			throw "Access denied: path escapes project directory";
		return absolute;
	}

	static function loadIgnore(root:String):Array<String> {
		final patterns:Array<String> = [];
		for (name in [".gitignore", ".ignore"]) {
			final path = NodePath.join(root, name);
			if (Fs.existsSync(path)) {
				for (pattern in FileIgnore.fromIgnoreText(Fs.readFileSync(path, "utf8")))
					patterns.push(pattern);
			}
		}
		return patterns;
	}

	static function textRead(root:String, file:String, content:String):FileReadResult {
		final diff = Git.diffFile(root, file);
		if (StringTools.trim(diff) == "")
			return {type: "text", content: content};
		final patch = patchFromDiff(file, diff);
		if (patch == null)
			return {type: "text", content: content, diff: diff};
		return {
			type: "text",
			content: content,
			diff: diff,
			patch: patch
		};
	}

	static function patchFromDiff(file:String, diff:String):Null<FilePatch> {
		final hunks:Array<FilePatchHunk> = [];
		var index:Null<String> = null;
		var current:Null<FilePatchHunk> = null;
		final hunkPattern = ~/^@@ -([0-9]+)(?:,([0-9]+))? \+([0-9]+)(?:,([0-9]+))? @@/;
		for (line in diff.split("\n")) {
			if (StringTools.startsWith(line, "index ")) {
				index = line.substr("index ".length);
				continue;
			}
			if (hunkPattern.match(line)) {
				current = {
					oldStart: matchedInt(hunkPattern, 1, 1),
					oldLines: matchedInt(hunkPattern, 2, 1),
					newStart: matchedInt(hunkPattern, 3, 1),
					newLines: matchedInt(hunkPattern, 4, 1),
					lines: [],
				};
				hunks.push(current);
				continue;
			}
			if (current != null && isPatchLine(line))
				current.lines.push(line);
		}
		if (hunks.length == 0)
			return null;
		return {
			oldFileName: file,
			newFileName: file,
			oldHeader: "old",
			newHeader: "new",
			hunks: hunks,
			index: index,
		};
	}

	static function matchedInt(pattern:EReg, group:Int, fallback:Int):Int {
		try {
			final value = pattern.matched(group);
			if (value == null || value == "")
				return fallback;
			final parsed = Std.parseInt(value);
			return parsed == null ? fallback : parsed;
		} catch (_:Dynamic) {
			return fallback;
		}
	}

	static function isPatchLine(line:String):Bool {
		return StringTools.startsWith(line, " ") || StringTools.startsWith(line, "+") || StringTools.startsWith(line, "-")
			|| StringTools.startsWith(line, "\\");
	}

	static function compareNode(a:FileNode, b:FileNode):Int {
		if (a.type != b.type)
			return a.type == "directory" ? -1 : 1;
		return Reflect.compare(a.name, b.name);
	}

	static function isImageByExtension(file:String):Bool {
		return IMAGE_MIME.exists(extension(file));
	}

	static function isTextByExtension(file:String):Bool {
		return TEXT_EXTENSIONS.indexOf(extension(file)) != -1;
	}

	static function isTextByName(file:String):Bool {
		return TEXT_NAMES.indexOf(NodePath.basename(file).toLowerCase()) != -1;
	}

	static function isBinaryByExtension(file:String):Bool {
		return BINARY_EXTENSIONS.indexOf(extension(file)) != -1;
	}

	static function imageMime(file:String):String {
		final mime = IMAGE_MIME.get(extension(file));
		return mime == null ? "image/" + extension(file) : mime;
	}

	static function extension(file:String):String {
		final ext = NodePath.extname(file).toLowerCase();
		return StringTools.startsWith(ext, ".") ? ext.substr(1) : ext;
	}

	static function normalize(path:String):String {
		return StringTools.replace(path, "\\", "/");
	}
}
