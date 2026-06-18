package opencodehx.util;

class Wildcard {
	public static function match(value:String, pattern:String):Bool {
		if (pattern == "*")
			return true;
		final regex = new EReg("^" + escape(pattern) + "$", "");
		return regex.match(value);
	}

	static function escape(pattern:String):String {
		final specials = "\\.+?^${}()|[]";
		final out = new StringBuf();
		for (i in 0...pattern.length) {
			final char = pattern.charAt(i);
			if (char == "*") {
				out.add(".*");
			} else {
				if (specials.indexOf(char) != -1)
					out.add("\\");
				out.add(char);
			}
		}
		return out.toString();
	}
}
