package opencodehx.smoke;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.Json;
import js.Syntax;
import js.lib.Error as JsError;
import opencodehx.resource.Resources;
import opencodehx.resource.Resources.ResourcePaths;
import opencodehx.util.DataUrl;
import opencodehx.util.ErrorTools;
import opencodehx.util.Format;
import opencodehx.util.Lazy;

class UtilSmoke {
	public static function run():Void {
		formatDuration();
		errorTools();
		lazy();
		dataUrl();
	}

	static function formatDuration():Void {
		eq(Format.formatDuration(0), "", "duration zero");
		eq(Format.formatDuration(-100), "", "duration negative");
		eq(Format.formatDuration(59), "59s", "duration seconds");
		eq(Format.formatDuration(60), "1m", "duration minute boundary");
		eq(Format.formatDuration(61), "1m 1s", "duration minute seconds");
		eq(Format.formatDuration(3599), "59m 59s", "duration hour boundary");
		eq(Format.formatDuration(3600), "1h", "duration hour");
		eq(Format.formatDuration(86399), "23h 59m", "duration day boundary");
		eq(Format.formatDuration(86400), "~1 day", "duration day");
		eq(Format.formatDuration(604799), "~6 days", "duration week boundary");
		eq(Format.formatDuration(604800), "~1 week", "duration week");
		eq(Format.formatDuration(1209600), "~2 weeks", "duration weeks");
	}

	static function lazy():Void {
		var calls = 0;
		final value = new Lazy(() -> {
			calls++;
			return "expensive value";
		});

		eq(calls, 0, "lazy before get");
		eq(value.get(), "expensive value", "lazy first get");
		eq(calls, 1, "lazy first call count");
		eq(value.get(), "expensive value", "lazy second get");
		eq(calls, 1, "lazy second call count");
		value.reset();
		eq(value.get(), "expensive value", "lazy reset get");
		eq(calls, 2, "lazy reset call count");
	}

	static function dataUrl():Void {
		final body = "{\n  \"ok\": true\n}\n";
		eq(DataUrl.decode("data:text/plain;base64,ewogICJvayI6IHRydWUKfQo="), body, "data-url base64");
		eq(DataUrl.decode("data:text/plain,hello%20world"), "hello world", "data-url plain");
		eq(DataUrl.decode("data:text/plain,hello+world"), "hello+world", "data-url plus parity");
		eq(DataUrl.decode("not-a-data-url"), "", "data-url missing comma");
	}

	static function errorTools():Void {
		final golden:Dynamic = Json.parse(Resources.text(ResourcePaths.known("errors/diagnostics.golden.json")));
		final util:Dynamic = Reflect.field(golden, "util");

		final native = new JsError("boom");
		final nativeUnknown = Unknown.fromBoundary(native);
		final nativeData = ErrorTools.data(nativeUnknown);
		eq(ErrorTools.message(nativeUnknown), Reflect.field(util, "nativeMessage"), "native error message");
		eq(dataString(nativeData, "type"), Reflect.field(util, "nativeType"), "native error type");
		eq(dataString(nativeData, "message"), Reflect.field(util, "nativeMessage"), "native error data message");
		eq(ErrorTools.format(nativeUnknown).indexOf("boom") != -1, true, "native error formatted");

		final record = {message: "bad input", code: "E_BAD"};
		final recordUnknown = Unknown.fromBoundary(record);
		final recordData = ErrorTools.data(recordUnknown);
		eq(ErrorTools.message(recordUnknown), Reflect.field(util, "recordMessage"), "record error message");
		eq(dataString(recordData, "message"), Reflect.field(util, "recordMessage"), "record error data message");
		eq(dataString(recordData, "code"), Reflect.field(util, "recordCode"), "record error code");

		// Upstream util/error tests use a JavaScript object literal with a custom
		// toString method. Keep this fixture at that JS boundary shape.
		final opaque:Dynamic = Syntax.code("({ toString() { return \"ResolveMessage: Cannot resolve module\"; } })");
		final opaqueUnknown = Unknown.fromBoundary(opaque);
		eq(ErrorTools.message(opaqueUnknown), Reflect.field(util, "opaqueMessage"), "opaque error message");
		eq(dataString(ErrorTools.data(opaqueUnknown), "message"), Reflect.field(util, "opaqueMessage"), "opaque error data message");
	}

	static function dataString(data:opencodehx.util.ErrorTools.ErrorData, field:String):String {
		final value = UnknownNarrow.string(data.get(field));
		return value == null ? "" : value;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
