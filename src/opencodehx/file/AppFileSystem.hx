package opencodehx.file;

import haxe.Json;
import js.lib.Uint8Array;
import opencodehx.externs.node.Buffer.NodeBufferData;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;

class AppFileSystem {
	public static function isDir(path:String):Bool {
		return Fs.existsSync(path) && Fs.statSync(path).isDirectory();
	}

	public static function isFile(path:String):Bool {
		return Fs.existsSync(path) && Fs.statSync(path).isFile();
	}

	public static function exists(path:String):Bool {
		return Fs.existsSync(path);
	}

	public static function remove(path:String):Void {
		Fs.rmSync(path, {recursive: true, force: true});
	}

	public static function ensureDir(path:String):Void {
		Fs.mkdirSync(path, {recursive: true});
	}

	public static function writeFileString(path:String, content:String):Void {
		ensureDir(NodePath.dirname(path));
		Fs.writeFileSync(path, content);
	}

	public static function readFileString(path:String):String {
		return Fs.readFileSync(path, "utf8");
	}

	public static function writeWithDirs(path:String, content:AppFileContent):Void {
		ensureDir(NodePath.dirname(path));
		switch content {
			case Text(value):
				Fs.writeFileSync(path, value);
			case Bytes(value):
				Fs.writeFileSync(path, value);
		}
	}

	public static function readFile(path:String):NodeBufferData {
		return Fs.readFileBufferSync(path);
	}

	// JSON payloads are an untyped runtime boundary; callers own domain narrowing.
	public static function writeJson(path:String, data:Dynamic):Void {
		writeFileString(path, Json.stringify(data));
	}

	public static function readJson(path:String):Dynamic {
		return Json.parse(readFileString(path));
	}

	public static function findUp(target:String, start:String, ?stop:String):Array<String> {
		return up({targets: [target], start: start, stop: stop});
	}

	public static function up(input:AppFileSystemUpInput):Array<String> {
		final out:Array<String> = [];
		final stop = input.stop == null ? null : NodePath.resolve(input.stop, ".");
		var current = NodePath.resolve(input.start, ".");
		while (true) {
			for (target in input.targets) {
				final candidate = NodePath.join(current, target);
				if (Fs.existsSync(candidate))
					out.push(candidate);
			}
			if (stop != null && current == stop)
				break;
			final parent = NodePath.dirname(current);
			if (parent == current)
				break;
			current = parent;
		}
		return out;
	}

	public static function glob(pattern:String, opts:AppFileSystemGlobOptions):Array<String> {
		final cwd = opts.cwd == null ? "." : opts.cwd;
		final absolute = opts.absolute == true;
		final out:Array<String> = [];
		for (file in walkFiles(cwd)) {
			final relative = normalize(NodePath.relative(cwd, file));
			if (globMatch(pattern, relative))
				out.push(absolute ? file : relative);
		}
		out.sort(Reflect.compare);
		return out;
	}

	public static function globUp(pattern:String, start:String, ?stop:String):Array<String> {
		final out:Array<String> = [];
		final stopPath = stop == null ? null : NodePath.resolve(stop, ".");
		var current = NodePath.resolve(start, ".");
		while (true) {
			for (file in glob(pattern, {cwd: current, absolute: true}))
				out.push(file);
			if (stopPath != null && current == stopPath)
				break;
			final parent = NodePath.dirname(current);
			if (parent == current)
				break;
			current = parent;
		}
		return out;
	}

	public static function globMatch(pattern:String, path:String):Bool {
		return FileIgnore.glob(pattern, normalize(path));
	}

	public static function mimeType(path:String):String {
		final ext = extension(path);
		return switch ext {
			case "json": "application/json";
			case "png": "image/png";
			case "jpg" | "jpeg": "image/jpeg";
			case "gif": "image/gif";
			case "webp": "image/webp";
			case "txt": "text/plain";
			case "html": "text/html";
			case "svg": "image/svg+xml";
			default: "application/octet-stream";
		}
	}

	public static function contains(root:String, target:String):Bool {
		return FileSystem.contains(root, target);
	}

	public static function overlaps(left:String, right:String):Bool {
		return contains(left, right) || contains(right, left);
	}

	static function walkFiles(root:String):Array<String> {
		final out:Array<String> = [];
		if (!Fs.existsSync(root))
			return out;
		for (entry in Fs.readdirSync(root, {withFileTypes: true})) {
			final name = Std.string(Reflect.field(entry, "name"));
			final absolute = NodePath.join(root, name);
			final isDirectory:Bool = Reflect.callMethod(entry, Reflect.field(entry, "isDirectory"), []);
			if (isDirectory) {
				for (file in walkFiles(absolute))
					out.push(file);
			} else {
				out.push(absolute);
			}
		}
		return out;
	}

	static function extension(path:String):String {
		final ext = NodePath.extname(path).toLowerCase();
		return StringTools.startsWith(ext, ".") ? ext.substr(1) : ext;
	}

	static function normalize(path:String):String {
		return StringTools.replace(path, "\\", "/");
	}
}

enum AppFileContent {
	Text(value:String);
	Bytes(value:Uint8Array);
}

typedef AppFileSystemUpInput = {
	final targets:Array<String>;
	final start:String;
	@:optional final stop:String;
}

typedef AppFileSystemGlobOptions = {
	@:optional final cwd:String;
	@:optional final absolute:Bool;
}
