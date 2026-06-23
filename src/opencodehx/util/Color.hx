package opencodehx.util;

typedef RgbColor = {
	final r:Int;
	final g:Int;
	final b:Int;
}

class Color {
	static final HEX = ~/^#[0-9a-fA-F]{6}$/;

	public static function isValidHex(hex:Null<String>):Bool {
		return hex != null && HEX.match(hex);
	}

	public static function hexToRgb(hex:String):RgbColor {
		return {
			r: parsePair(hex, 1),
			g: parsePair(hex, 3),
			b: parsePair(hex, 5),
		};
	}

	public static function hexToAnsiBold(hex:Null<String>):Null<String> {
		if (!isValidHex(hex))
			return null;
		final rgb = hexToRgb(hex);
		return '\x1b[38;2;${rgb.r};${rgb.g};${rgb.b}m\x1b[1m';
	}

	static function parsePair(hex:String, index:Int):Int {
		final parsed = Std.parseInt("0x" + hex.substr(index, 2));
		return parsed == null ? 0 : parsed;
	}
}
