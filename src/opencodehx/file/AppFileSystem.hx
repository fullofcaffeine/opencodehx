package opencodehx.file;

import haxe.Json;
import js.lib.Promise;
import js.lib.Uint8Array;
import opencodehx.externs.node.Buffer;
import opencodehx.externs.node.ChildProcess.NodeReadableStream;
import opencodehx.externs.node.Buffer.NodeBufferData;
import opencodehx.externs.node.Fs;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.externs.web.WebStreams.WebReadableStreamReadResult;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;

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

	public static function size(path:String):Int {
		try {
			final stat = Fs.statSync(path);
			return stat.size == null ? 0 : Std.int(stat.size);
		} catch (_:Dynamic) {
			return 0;
		}
	}

	public static function ensureDir(path:String):Void {
		Fs.mkdirSync(path, {recursive: true});
	}

	public static function writeFileString(path:String, content:String, ?mode:Int):Void {
		ensureDir(NodePath.dirname(path));
		Fs.writeFileSync(path, content, writeOptions(mode));
	}

	public static function readFileString(path:String):String {
		return Fs.readFileSync(path, "utf8");
	}

	public static function writeWithDirs(path:String, content:AppFileContent, ?mode:Int):Void {
		ensureDir(NodePath.dirname(path));
		final options = writeOptions(mode);
		switch content {
			case Text(value):
				Fs.writeFileSync(path, value, options);
			case Bytes(value):
				Fs.writeFileSync(path, value, options);
		}
	}

	@:async
	public static function writeStream(path:String, stream:WebReadableStream<Uint8Array>, ?mode:Int):Promise<Void> {
		final reader = stream.getReader();
		final chunks:Array<Uint8Array> = [];
		try {
			while (true) {
				final result:WebReadableStreamReadResult<Uint8Array> = @:await reader.read();
				if (result.done)
					break;
				if (result.value != null)
					chunks.push(result.value);
			}
		} catch (error:haxe.Exception) {
			@:await reader.cancel();
			throw error;
		}
		writeChunks(path, chunks, mode);
	}

	public static function writeNodeStream(path:String, stream:NodeReadableStream, ?mode:Int):Promise<Void> {
		return new Promise<Void>((resolve, reject) -> {
			final chunks:Array<Uint8Array> = [];
			final resolveVoid:Void->Void = cast resolve;
			stream.on("data", (chunk:Dynamic) -> chunks.push(nodeChunkBytes(chunk)));
			stream.on("error", (error:Dynamic) -> reject(error));
			stream.on("end", () -> {
				try {
					writeChunks(path, chunks, mode);
					resolveVoid();
				} catch (error:Dynamic) {
					reject(error);
				}
			});
		});
	}

	public static function readFile(path:String):NodeBufferData {
		return Fs.readFileBufferSync(path);
	}

	// JSON payloads are an untyped runtime boundary; callers own domain narrowing.
	public static function writeJson(path:String, data:Dynamic, ?mode:Int):Void {
		writeFileString(path, Json.stringify(data, null, "  "), mode);
	}

	public static function readJson(path:String):Dynamic {
		return Json.parse(readFileString(path));
	}

	public static function findUp(target:String, start:String, ?stop:String):Array<String> {
		return up({targets: [target], start: start, stop: stop});
	}

	public static function findUpMany(targets:Array<String>, start:String, ?stop:String, ?options:AppFileSystemFindUpOptions):Array<String> {
		return up({
			targets: targets,
			start: start,
			stop: stop,
			rootFirst: options != null && options.rootFirst == true});
	}

	public static function up(input:AppFileSystemUpInput):Array<String> {
		final out:Array<String> = [];
		final stop = input.stop == null ? null : NodePath.resolve(input.stop, ".");
		var current = NodePath.resolve(input.start, ".");
		final dirs:Array<String> = [];
		while (true) {
			dirs.push(current);
			if (stop != null && current == stop)
				break;
			final parent = NodePath.dirname(current);
			if (parent == current)
				break;
			current = parent;
		}
		if (input.rootFirst == true)
			dirs.reverse();
		for (dir in dirs) {
			for (target in input.targets) {
				final candidate = NodePath.join(dir, target);
				if (Fs.existsSync(candidate))
					out.push(candidate);
			}
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
			case "js": "text/javascript";
			case "ts": "application/typescript";
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

	public static function windowsPath(path:String):String {
		return NodeProcess.windowsPath(path);
	}

	public static function normalizePath(path:String):String {
		if (NodeProcess.platform() != "win32")
			return path;
		final resolved = NodePath.normalize(NodePath.windowsResolve(windowsPath(path), "."));
		try {
			return NodePath.normalize(Fs.realpathSync(resolved));
		} catch (_:Dynamic) {
			return resolved;
		}
	}

	public static function normalizePathPattern(path:String):String {
		if (NodeProcess.platform() != "win32" || path == "*")
			return path;
		final pattern = ~/^(.*)[\\\/]\*$/;
		if (!pattern.match(path))
			return normalizePath(path);
		final dir = driveRoot(pattern.matched(1));
		return NodePath.windowsJoin(normalizePath(dir), "*");
	}

	public static function resolve(path:String):String {
		final resolved = NodePath.resolve(windowsPath(path), ".");
		try {
			return normalizePath(Fs.realpathSync(resolved));
		} catch (error:Dynamic) {
			if (errorCode(error) == "ENOENT")
				return normalizePath(resolved);
			throw error;
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

	static function writeChunks(path:String, chunks:Array<Uint8Array>, ?mode:Int):Void {
		ensureDir(NodePath.dirname(path));
		final options = writeOptions(mode);
		if (chunks.length == 0) {
			Fs.writeFileSync(path, Uint8Array.from([]), options);
			return;
		}
		if (chunks.length == 1) {
			Fs.writeFileSync(path, chunks[0], options);
			return;
		}
		Fs.writeFileSync(path, Buffer.concat(chunks), options);
	}

	static function writeOptions(?mode:Int):Dynamic {
		return mode == null ? null : {mode: mode};
	}

	static function nodeChunkBytes(chunk:Dynamic):Uint8Array {
		if (Std.isOfType(chunk, String))
			return Buffer.from(Std.string(chunk), "utf8").subarray(0);
		// Node Readable streams can emit Buffer/Uint8Array-like chunks from
		// third-party sources. Keep the cast at the stream boundary and store
		// only copied bytes in the filesystem helper.
		final data:NodeBufferData = cast chunk;
		return data.subarray(0);
	}

	static function extension(path:String):String {
		final ext = NodePath.extname(path).toLowerCase();
		return StringTools.startsWith(ext, ".") ? ext.substr(1) : ext;
	}

	static function normalize(path:String):String {
		return StringTools.replace(path, "\\", "/");
	}

	static function driveRoot(path:String):String {
		return ~/^[A-Za-z]:$/.match(path) ? path + "\\" : path;
	}

	static function errorCode(error:Dynamic):String {
		final code = Reflect.field(error, "code");
		return code == null ? "" : Std.string(code);
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
	@:optional final rootFirst:Bool;
}

typedef AppFileSystemGlobOptions = {
	@:optional final cwd:String;
	@:optional final absolute:Bool;
}

typedef AppFileSystemFindUpOptions = {
	@:optional final rootFirst:Bool;
}
