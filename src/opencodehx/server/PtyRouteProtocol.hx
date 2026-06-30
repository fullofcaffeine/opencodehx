package opencodehx.server;

import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
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

	static function object(raw:Unknown):Null<UnknownRecord> {
		return UnknownNarrow.record(raw);
	}

	static function optionalString(data:UnknownRecord, field:String):{value:Null<String>, issue:Null<String>} {
		if (!data.hasOwn(field))
			return {value: null, issue: null};
		final value = data.get(field);
		if (isAbsent(value))
			return {value: null, issue: null};
		final stringValue = UnknownNarrow.string(value);
		if (stringValue == null)
			return {value: null, issue: '${field}: expected string'};
		return {value: stringValue, issue: null};
	}

	static function optionalStringArray(data:UnknownRecord, field:String):{value:Null<Array<String>>, issue:Null<String>} {
		if (!data.hasOwn(field))
			return {value: null, issue: null};
		final value = data.get(field);
		if (isAbsent(value))
			return {value: null, issue: null};
		final array = UnknownNarrow.array(value);
		if (array == null)
			return {value: null, issue: '${field}: expected string array'};
		return decodeStringArray(array, field);
	}

	static function decodeStringArray(value:UnknownArray, field:String):{value:Null<Array<String>>, issue:Null<String>} {
		final out:Array<String> = [];
		for (index in 0...value.length) {
			final item = UnknownNarrow.string(value.get(index));
			if (item == null)
				return {value: null, issue: '${field}: expected string array'};
			out.push(item);
		}
		return {value: out, issue: null};
	}

	static function optionalStringMap(data:UnknownRecord, field:String):{value:Null<DynamicAccess<String>>, issue:Null<String>} {
		if (!data.hasOwn(field))
			return {value: null, issue: null};
		final value = data.get(field);
		if (isAbsent(value))
			return {value: null, issue: null};
		final record = UnknownNarrow.record(value);
		if (record == null)
			return {value: null, issue: '${field}: expected string map'};
		final out = new DynamicAccess<String>();
		for (key in record.keys()) {
			final item = UnknownNarrow.string(record.get(key));
			if (item == null)
				return {value: null, issue: '${field}.${key}: expected string'};
			out.set(key, item);
		}
		return {value: out, issue: null};
	}

	static function optionalSize(data:UnknownRecord, field:String):{value:Null<PtySize>, issue:Null<String>} {
		if (!data.hasOwn(field))
			return {value: null, issue: null};
		final value = data.get(field);
		if (isAbsent(value))
			return {value: null, issue: null};
		final record = UnknownNarrow.record(value);
		if (record == null)
			return {value: null, issue: '${field}: expected object'};
		final cols = requiredInt(record, "cols", field);
		if (cols.issue != null)
			return {value: null, issue: cols.issue};
		final rows = requiredInt(record, "rows", field);
		if (rows.issue != null)
			return {value: null, issue: rows.issue};
		return {value: {cols: cols.value, rows: rows.value}, issue: null};
	}

	static function requiredInt(data:UnknownRecord, field:String, owner:String):{value:Int, issue:Null<String>} {
		if (!data.hasOwn(field))
			return {value: 0, issue: '${owner}.${field}: expected integer'};
		final value = data.get(field);
		if (isAbsent(value))
			return {value: 0, issue: '${owner}.${field}: expected integer'};
		final intValue = UnknownNarrow.int32(value);
		if (intValue == null)
			return {value: 0, issue: '${owner}.${field}: expected integer'};
		return {value: intValue, issue: null};
	}

	static inline function isAbsent(value:Unknown):Bool {
		return UnknownNarrow.isNull(value) || UnknownNarrow.isUndefined(value);
	}
}
