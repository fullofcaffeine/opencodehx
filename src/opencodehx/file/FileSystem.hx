package opencodehx.file;

import opencodehx.externs.node.Fs;
import opencodehx.file.Ripgrep.SearchResult;
import opencodehx.host.node.NodePath;

typedef FileNode = {
	final name:String;
	final path:String;
	final absolute:String;
	final type:String;
	final ignored:Bool;
}

class FileSystem {
	public static function contains(root:String, target:String):Bool {
		final relative = normalize(NodePath.relative(NodePath.resolve(root, "."), NodePath.resolve(target, ".")));
		return relative == "" || (!StringTools.startsWith(relative, "..") && !NodePath.isAbsolute(relative));
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

	static function compareNode(a:FileNode, b:FileNode):Int {
		if (a.type != b.type)
			return a.type == "directory" ? -1 : 1;
		return Reflect.compare(a.name, b.name);
	}

	static function normalize(path:String):String {
		return StringTools.replace(path, "\\", "/");
	}
}
