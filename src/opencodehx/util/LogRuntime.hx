package opencodehx.util;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import js.lib.Date as JsDate;
import opencodehx.util.Compare.compareString;

typedef LogInitOptions = {
	final print:Bool;
	@:optional final dev:Bool;
}

class LogRuntime {
	static inline final DEFAULT_KEEP = 10;

	static final timestampedLog = ~/^\d{4}-\d{2}-\d{2}T\d{6}\.log$/;

	public static function init(dir:String, options:LogInitOptions):Null<String> {
		Fs.mkdirSync(dir, {recursive: true});
		cleanup(dir);
		if (options.print)
			return null;

		final name = options.dev == true ? "dev.log" : timestampName(new JsDate());
		final path = NodePath.join(dir, name);
		Fs.writeFileSync(path, "");
		return path;
	}

	public static function cleanup(dir:String, ?keep:Int):Array<String> {
		if (!Fs.existsSync(dir))
			return [];

		final limit = keep == null ? DEFAULT_KEEP : keep;
		final files = timestampedFiles(dir);
		if (files.length <= limit)
			return [];

		final doomed = files.slice(0, files.length - limit);
		for (file in doomed) {
			try {
				Fs.unlinkSync(NodePath.join(dir, file));
			} catch (_:Dynamic) {}
		}
		return doomed;
	}

	static function timestampedFiles(dir:String):Array<String> {
		final result:Array<String> = [];
		for (entry in Fs.readdirNamesSync(dir)) {
			if (NodePath.basename(entry) == entry && timestampedLog.match(entry))
				result.push(entry);
		}
		result.sort(compareString);
		return result;
	}

	static function timestampName(date:JsDate):String {
		final year = date.getFullYear();
		final month = pad2(date.getMonth() + 1);
		final day = pad2(date.getDate());
		final hour = pad2(date.getHours());
		final minute = pad2(date.getMinutes());
		final second = pad2(date.getSeconds());
		return '${year}-${month}-${day}T${hour}${minute}${second}.log';
	}

	static function pad2(value:Int):String {
		return value < 10 ? "0" + value : Std.string(value);
	}
}
