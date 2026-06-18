package opencodehx.test.spec;

import js.lib.Promise;
import opencodehx.test.UnitSpec;
import opencodehx.util.Format;

class FormatSpec {
	static function main():Void {
		UnitSpec.describe("opencodehx.util.Format", () -> {
			UnitSpec.test("formats compact durations", () -> {
				UnitSpec.expect(Format.formatDuration(0)).toBe("");
				UnitSpec.expect(Format.formatDuration(61)).toBe("1m 1s");
				UnitSpec.expect(Format.formatDuration(3600)).toBe("1h");
				UnitSpec.expect(Format.formatDuration(1209600)).toBe("~2 weeks");
			});
			UnitSpec.testAsync("supports async runner callbacks", @:async function():Promise<Void> {
				final seconds = @:await Promise.resolve(61);
				UnitSpec.expect(Format.formatDuration(seconds)).toBe("1m 1s");
			});
		});
	}
}
