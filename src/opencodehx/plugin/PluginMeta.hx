package opencodehx.plugin;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.DynamicAccess;
import haxe.Json;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.plugin.PluginShared;
import opencodehx.plugin.PluginShared.PluginSource;

typedef PluginMetaEntry = {
	final id:String;
	final source:PluginSource;
	final spec:String;
	final target:String;
	@:optional final requested:String;
	@:optional final version:String;
	@:optional final modified:Float;
	final first_time:Float;
	final last_time:Float;
	final time_changed:Float;
	final load_count:Int;
	final fingerprint:String;
}

typedef PluginMetaTouch = {
	final state:String;
	final entry:PluginMetaEntry;
}

class PluginMeta {
	final file:String;
	final now:Void->Float;

	public function new(file:String, ?now:Void->Float) {
		this.file = file;
		this.now = now == null ? runtimeNow : now;
	}

	public function touch(spec:String, target:String, id:String):PluginMetaTouch {
		final store = read();
		final core = core(spec, target, id);
		final previous = store.get(id);
		final timestamp = now();
		final entry:PluginMetaEntry = {
			id: core.id,
			source: core.source,
			spec: core.spec,
			target: core.target,
			requested: core.requested,
			version: core.version,
			modified: core.modified,
			first_time: previous == null ? timestamp : previous.first_time,
			last_time: timestamp,
			time_changed: previous == null || previous.fingerprint != core.fingerprint ? timestamp : previous.time_changed,
			load_count: previous == null ? 1 : previous.load_count + 1,
			fingerprint: core.fingerprint,
		};
		final state = previous == null ? "first" : previous.fingerprint == entry.fingerprint ? "same" : "updated";
		store.set(id, entry);
		write(store);
		return {state: state, entry: entry};
	}

	public function list():DynamicAccess<PluginMetaEntry> {
		return read();
	}

	function core(spec:String, target:String, id:String):PluginMetaEntry {
		final source = PluginShared.pluginSource(spec);
		if (source == File) {
			final filePath = StringTools.startsWith(target, "file://") ? opencodehx.externs.node.Url.fileURLToPath(target) : target;
			final modified = Fs.existsSync(filePath) ? Fs.statSync(filePath).mtimeMs : null;
			final fingerprint = target + "|" + (modified == null ? "" : stringValue(modified));
			return empty(id, source, spec, target, null, null, modified, fingerprint);
		}

		final parsed = PluginShared.parsePluginSpecifier(spec);
		final pkg = PluginShared.readPluginPackage(target);
		final version = pkg == null ? null : UnknownNarrow.string(pkg.json.get("version"));
		final fingerprint = target + "|" + parsed.version + "|" + (version == null ? "" : version);
		return empty(id, source, spec, target, parsed.version, version, null, fingerprint);
	}

	function empty(id:String, source:PluginSource, spec:String, target:String, requested:Null<String>, version:Null<String>, modified:Null<Float>,
			fingerprint:String):PluginMetaEntry {
		return {
			id: id,
			source: source,
			spec: spec,
			target: target,
			requested: requested,
			version: version,
			modified: modified,
			first_time: 0,
			last_time: 0,
			time_changed: 0,
			load_count: 0,
			fingerprint: fingerprint,
		};
	}

	function read():DynamicAccess<PluginMetaEntry> {
		final out = new DynamicAccess<PluginMetaEntry>();
		if (!Fs.existsSync(file))
			return out;
		final root = UnknownNarrow.record(Unknown.fromBoundary(Json.parse(Fs.readFileSync(file, "utf8"))));
		if (root == null)
			return out;
		for (id in root.keys()) {
			final item = UnknownNarrow.record(root.get(id));
			if (item != null)
				out.set(id, decodeEntry(item));
		}
		return out;
	}

	function write(store:DynamicAccess<PluginMetaEntry>):Void {
		Fs.mkdirSync(NodePath.dirname(file), {recursive: true});
		Fs.writeFileSync(file, Json.stringify(store, null, "  "), {encoding: "utf8"});
	}

	static function decodeEntry(item:UnknownRecord):PluginMetaEntry {
		return {
			id: stringField(item, "id"),
			source: sourceField(item),
			spec: stringField(item, "spec"),
			target: stringField(item, "target"),
			requested: optionalString(item, "requested"),
			version: optionalString(item, "version"),
			modified: optionalFloat(item, "modified"),
			first_time: floatField(item, "first_time"),
			last_time: floatField(item, "last_time"),
			time_changed: floatField(item, "time_changed"),
			load_count: intField(item, "load_count"),
			fingerprint: stringField(item, "fingerprint"),
		};
	}

	static function stringField(data:UnknownRecord, field:String):String {
		final value = UnknownNarrow.string(data.get(field));
		return value == null ? "" : value;
	}

	static function optionalString(data:UnknownRecord, field:String):Null<String> {
		return UnknownNarrow.string(data.get(field));
	}

	static function optionalFloat(data:UnknownRecord, field:String):Null<Float> {
		return UnknownNarrow.finiteNumber(data.get(field));
	}

	static function floatField(data:UnknownRecord, field:String):Float {
		final value = UnknownNarrow.finiteNumber(data.get(field));
		return value == null ? 0 : value;
	}

	static function intField(data:UnknownRecord, field:String):Int {
		final value = UnknownNarrow.int32(data.get(field));
		return value == null ? 0 : value;
	}

	static function sourceField(data:UnknownRecord):PluginSource {
		return stringField(data, "source") == "file" ? File : Npm;
	}

	static function stringValue(value:Float):String {
		return Std.string(value);
	}

	static function runtimeNow():Float {
		// Plugin metadata timestamps mirror JavaScript Date.now(). Avoid Haxe
		// Date here because its generated prototype metadata is not accepted by
		// this project's strict TypeScript gate.
		return js.Syntax.code("Date.now()");
	}
}
