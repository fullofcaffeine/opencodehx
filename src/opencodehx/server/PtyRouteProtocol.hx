package opencodehx.server;

import genes.ts.Unknown;
import haxe.DynamicAccess;
import opencodehx.pty.PtyTypes.PtyCreateInput;
import opencodehx.pty.PtyTypes.PtySize;
import opencodehx.pty.PtyTypes.PtyUpdateInput;
import opencodehx.server.ServerProtocol.DecodeResult;

class PtyRouteProtocol {
	public static function decodeCreate(raw:Unknown):DecodeResult<PtyCreateInput> {
		final data = object(raw);
		if (data == null)
			return Rejected("body: expected object");
		final command = optionalString(data, "command");
		if (command.issue != null)
			return Rejected(command.issue);
		final cwd = optionalString(data, "cwd");
		if (cwd.issue != null)
			return Rejected(cwd.issue);
		final title = optionalString(data, "title");
		if (title.issue != null)
			return Rejected(title.issue);
		final args = optionalStringArray(data, "args");
		if (args.issue != null)
			return Rejected(args.issue);
		final env = optionalStringMap(data, "env");
		if (env.issue != null)
			return Rejected(env.issue);
		return Decoded({
			command: command.value,
			cwd: cwd.value,
			title: title.value,
			args: args.value,
			env: env.value,
		});
	}

	public static function decodeUpdate(raw:Unknown):DecodeResult<PtyUpdateInput> {
		final data = object(raw);
		if (data == null)
			return Rejected("body: expected object");
		final title = optionalString(data, "title");
		if (title.issue != null)
			return Rejected(title.issue);
		final size = optionalSize(data, "size");
		if (size.issue != null)
			return Rejected(size.issue);
		return Decoded({
			title: title.value,
			size: size.value,
		});
	}

	static function object(raw:Unknown):Null<Dynamic> {
		// Justified Dynamic boundary: PTY route bodies arrive as generated TS
		// `unknown`. Haxe reflection needs Dynamic to inspect JSON fields, so
		// every access stays local and returns typed PTY DTOs or an error.
		final data:Dynamic = cast raw;
		if (data == null || !Reflect.isObject(data) || Std.isOfType(data, Array))
			return null;
		return data;
	}

	static function optionalString(data:Dynamic, field:String):{value:Null<String>, issue:Null<String>} {
		if (!Reflect.hasField(data, field) || Reflect.field(data, field) == null)
			return {value: null, issue: null};
		final value:Dynamic = Reflect.field(data, field);
		if (!Std.isOfType(value, String))
			return {value: null, issue: '${field}: expected string'};
		return {value: value, issue: null};
	}

	static function optionalStringArray(data:Dynamic, field:String):{value:Null<Array<String>>, issue:Null<String>} {
		if (!Reflect.hasField(data, field) || Reflect.field(data, field) == null)
			return {value: null, issue: null};
		final value:Dynamic = Reflect.field(data, field);
		if (!Std.isOfType(value, Array))
			return {value: null, issue: '${field}: expected string array'};
		final out:Array<String> = [];
		for (item in (value : Array<Dynamic>)) {
			if (!Std.isOfType(item, String))
				return {value: null, issue: '${field}: expected string array'};
			out.push(item);
		}
		return {value: out, issue: null};
	}

	static function optionalStringMap(data:Dynamic, field:String):{value:Null<DynamicAccess<String>>, issue:Null<String>} {
		if (!Reflect.hasField(data, field) || Reflect.field(data, field) == null)
			return {value: null, issue: null};
		final value:Dynamic = Reflect.field(data, field);
		if (!Reflect.isObject(value) || Std.isOfType(value, Array))
			return {value: null, issue: '${field}: expected string map'};
		final out = new DynamicAccess<String>();
		for (key in Reflect.fields(value)) {
			final item:Dynamic = Reflect.field(value, key);
			if (!Std.isOfType(item, String))
				return {value: null, issue: '${field}.${key}: expected string'};
			out.set(key, item);
		}
		return {value: out, issue: null};
	}

	static function optionalSize(data:Dynamic, field:String):{value:Null<PtySize>, issue:Null<String>} {
		if (!Reflect.hasField(data, field) || Reflect.field(data, field) == null)
			return {value: null, issue: null};
		final value:Dynamic = Reflect.field(data, field);
		if (!Reflect.isObject(value) || Std.isOfType(value, Array))
			return {value: null, issue: '${field}: expected object'};
		final cols = requiredInt(value, "cols", field);
		if (cols.issue != null)
			return {value: null, issue: cols.issue};
		final rows = requiredInt(value, "rows", field);
		if (rows.issue != null)
			return {value: null, issue: rows.issue};
		return {value: {cols: cols.value, rows: rows.value}, issue: null};
	}

	static function requiredInt(data:Dynamic, field:String, owner:String):{value:Int, issue:Null<String>} {
		if (!Reflect.hasField(data, field) || Reflect.field(data, field) == null)
			return {value: 0, issue: '${owner}.${field}: expected integer'};
		final value:Dynamic = Reflect.field(data, field);
		if (!Std.isOfType(value, Int) && !Std.isOfType(value, Float))
			return {value: 0, issue: '${owner}.${field}: expected integer'};
		final number:Float = value;
		if (Math.isNaN(number))
			return {value: 0, issue: '${owner}.${field}: expected integer'};
		return {value: Std.int(number), issue: null};
	}
}
