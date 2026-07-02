package opencodehx.storage;

import genes.ts.JsonCodec;
import genes.ts.JsonCodec.JsonDecode;
import genes.ts.JsonValue;
import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.storage.StorageError.StorageException;
import opencodehx.storage.StorageError.StorageFailure;
import opencodehx.util.Compare.compareString;

/**
 * File-backed JSON key/value storage matching the portable surface of
 * upstream `Storage.Service`.
 */
class StorageJsonRuntime {
	final root:String;
	final updateQueues:Map<String, Promise<Bool>>;

	public function new(root:String) {
		this.root = root;
		updateQueues = new Map();
		Fs.mkdirSync(root, {recursive: true});
	}

	public function write(key:Array<String>, value:JsonValue):Void {
		final target = filePath(key);
		Fs.mkdirSync(NodePath.dirname(target), {recursive: true});
		Fs.writeFileSync(target, JsonCodec.stringify(value));
	}

	public function read(key:Array<String>):JsonValue {
		final target = filePath(key);
		if (!Fs.existsSync(target))
			throw new StorageException(NotFound('Missing storage key ${key.join("/")}'));
		return parseFile(target);
	}

	public function update(key:Array<String>, change:JsonValue->JsonValue):Void {
		write(key, change(read(key)));
	}

	public function updateQueued(key:Array<String>, change:JsonValue->Promise<JsonValue>):Promise<Void> {
		final queueKey = keyID(key);
		final previous = updateQueues.get(queueKey);
		final ready = previous == null ? Promise.resolve(true) : previous;
		final operation:Promise<Void> = ready.then(_ -> {
			final current = read(key);
			return change(current).then(next -> {
				write(key, next);
				return null;
			});
		});
		updateQueues.set(queueKey, operation.then(_ -> true).catchError(_ -> true));
		return operation;
	}

	public function remove(key:Array<String>):Void {
		Fs.rmSync(filePath(key), {force: true});
	}

	public function list(prefix:Array<String>):Array<Array<String>> {
		final start = directoryPath(prefix);
		if (!Fs.existsSync(start))
			return [];
		final out:Array<Array<String>> = [];
		collect(start, prefix.copy(), out);
		out.sort(compareKeys);
		return out;
	}

	function collect(dir:String, prefix:Array<String>, out:Array<Array<String>>):Void {
		final names = Fs.readdirNamesSync(dir);
		for (name in names) {
			final path = NodePath.join(dir, name);
			final stat = Fs.statSync(path);
			if (stat.isDirectory()) {
				final nested = prefix.copy();
				nested.push(name);
				collect(path, nested, out);
				continue;
			}
			if (!stat.isFile() || !StringTools.endsWith(name, ".json"))
				continue;
			final key = prefix.copy();
			key.push(name.substr(0, name.length - ".json".length));
			out.push(key);
		}
	}

	function parseFile(path:String):JsonValue {
		return switch JsonCodec.parse(Fs.readFileSync(path, "utf8")) {
			case Ok(value):
				value;
			case Error(error):
				throw new StorageException(InvalidRow(path, [error.message]));
		}
	}

	function filePath(key:Array<String>):String {
		if (key.length == 0)
			throw new StorageException(StorageFailure.NotFound("Storage key must not be empty"));
		final parts = key.copy();
		parts[parts.length - 1] = parts[parts.length - 1] + ".json";
		return directoryPath(parts);
	}

	function directoryPath(parts:Array<String>):String {
		var path = root;
		for (part in parts)
			path = NodePath.join(path, part);
		return path;
	}

	static function compareKeys(a:Array<String>, b:Array<String>):Int {
		return compareString(a.join("\n"), b.join("\n"));
	}

	static function keyID(key:Array<String>):String {
		return key.join("\n");
	}
}
