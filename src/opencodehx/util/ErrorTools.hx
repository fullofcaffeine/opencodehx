package opencodehx.util;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.DynamicAccess;
import haxe.Json;
import haxe.Exception;
import js.Syntax;
import js.lib.Error as JsError;

typedef ErrorData = DynamicAccess<Unknown>;

class ErrorTools {
	public static function format(error:Unknown):String {
		if (Std.isOfType(error, JsError)) {
			final native:JsError = cast error;
			if (native.stack != null && native.stack != "")
				return native.stack;
			return '${native.name}: ${native.message}';
		}

		if (Std.isOfType(error, Exception)) {
			final exception:Exception = cast error;
			return exception.message == null ? Std.string(error) : exception.message;
		}

		final record = record(error);
		if (record != null) {
			try {
				return Json.stringify(error, null, "  ");
			} catch (_:Dynamic) {
				// JavaScript can throw arbitrary values while stringifying proxies or
				// circular records. This boundary returns the same stable fallback as
				// upstream's util/error formatter.
				return "Unexpected error (unserializable)";
			}
		}

		return jsString(error);
	}

	public static function message(error:Unknown):String {
		if (Std.isOfType(error, JsError)) {
			final native:JsError = cast error;
			if (native.message != null && native.message != "")
				return native.message;
			if (native.name != null && native.name != "")
				return native.name;
		}

		if (Std.isOfType(error, Exception)) {
			final exception:Exception = cast error;
			if (exception.message != null && exception.message != "")
				return exception.message;
		}

		final record = record(error);
		if (record != null) {
			final ownMessage = UnknownNarrow.string(record.get("message"));
			if (ownMessage != null && ownMessage != "")
				return ownMessage;
			final data = UnknownNarrow.record(record.get("data"));
			if (data != null) {
				final dataMessage = UnknownNarrow.string(data.get("message"));
				if (dataMessage != null && dataMessage != "")
					return dataMessage;
			}
		}

		final text = jsString(error);
		if (text != "" && text != "[object Object]")
			return text;

		final formatted = format(error);
		if (formatted != "" && formatted != "{}")
			return formatted;
		return "unknown error";
	}

	public static function data(error:Unknown):ErrorData {
		final out = new DynamicAccess<Unknown>();
		if (Std.isOfType(error, JsError)) {
			final native:JsError = cast error;
			out.set("type", Unknown.fromBoundary(native.name));
			out.set("message", Unknown.fromBoundary(message(error)));
			if (native.stack != null)
				out.set("stack", Unknown.fromBoundary(native.stack));
			final cause = field(error, "cause");
			if (!isUndefined(cause))
				out.set("cause", Unknown.fromBoundary(format(cause)));
			out.set("formatted", Unknown.fromBoundary(formatted(error)));
			return out;
		}

		final record = record(error);
		if (record == null) {
			out.set("type", Unknown.fromBoundary(jsTypeOf(error)));
			out.set("message", Unknown.fromBoundary(message(error)));
			out.set("formatted", Unknown.fromBoundary(formatted(error)));
			return out;
		}

		for (key in record.keys()) {
			final value = record.get(key);
			if (!UnknownNarrow.isUndefined(value))
				out.set(key, dataValue(value));
		}
		if (!isString(out.get("message")))
			out.set("message", Unknown.fromBoundary(message(error)));
		if (!isString(out.get("type"))) {
			final name = constructorName(error);
			if (name != null)
				out.set("type", Unknown.fromBoundary(name));
		}
		out.set("formatted", Unknown.fromBoundary(formatted(error)));
		return out;
	}

	static function formatted(error:Unknown):String {
		final value = format(error);
		return value == "{}" ? jsString(error) : value;
	}

	static function record(error:Unknown):Null<UnknownRecord> {
		return UnknownNarrow.record(error);
	}

	static function dataValue(value:Unknown):Unknown {
		final text = UnknownNarrow.string(value);
		if (text != null)
			return Unknown.fromBoundary(text);
		final number = UnknownNarrow.number(value);
		if (number != null)
			return Unknown.fromBoundary(number);
		final bool = UnknownNarrow.bool(value);
		if (bool != null)
			return Unknown.fromBoundary(bool);

		if (Std.isOfType(value, JsError)) {
			final native:JsError = cast value;
			return Unknown.fromBoundary(native.message);
		}
		return Unknown.fromBoundary(jsString(value));
	}

	static function isString(value:Unknown):Bool {
		return Syntax.code("typeof ({0}) === \"string\"", value);
	}

	static function isUndefined(value:Unknown):Bool {
		return Syntax.code("({0}) === undefined", value);
	}

	static function field(value:Unknown, name:String):Unknown {
		#if genes.ts
		return Unknown.fromBoundary(Syntax.code("({0}) == null ? undefined : ({0} as Record<string, unknown>)[{1}]", value, name));
		#else
		return Unknown.fromBoundary(Syntax.code("({0}) == null ? undefined : ({0})[{1}]", value, name));
		#end
	}

	static function jsTypeOf(value:Unknown):String {
		return Syntax.code("typeof ({0})", value);
	}

	static function jsString(value:Unknown):String {
		return Syntax.code("String({0})", value);
	}

	static function constructorName(value:Unknown):Null<String> {
		return Syntax.code("({0}) != null && ({0}).constructor && typeof ({0}).constructor.name === \"string\" ? ({0}).constructor.name : null", value);
	}
}
