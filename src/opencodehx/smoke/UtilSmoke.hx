package opencodehx.smoke;

import opencodehx.util.DataUrl;
import opencodehx.util.Format;
import opencodehx.util.Lazy;

class UtilSmoke {
	public static function run():Void {
		formatDuration();
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

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
