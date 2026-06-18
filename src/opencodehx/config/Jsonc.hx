package opencodehx.config;

import haxe.Json;
import opencodehx.config.ConfigError.ConfigException;

class Jsonc {
	public static function parse(text:String, path:String):Dynamic {
		final normalized = removeTrailingCommas(stripComments(text));
		try {
			return Json.parse(normalized);
		} catch (error:Dynamic) {
			throw new ConfigException(JsonError(path, Std.string(error)));
		}
	}

	static function stripComments(text:String):String {
		final out = new StringBuf();
		var i = 0;
		var inString = false;
		var escaped = false;
		var lineComment = false;
		var blockComment = false;

		while (i < text.length) {
			final c = text.charAt(i);
			final next = i + 1 < text.length ? text.charAt(i + 1) : "";

			if (lineComment) {
				if (c == "\n" || c == "\r") {
					lineComment = false;
					out.add(c);
				} else {
					out.add(" ");
				}
				i++;
				continue;
			}

			if (blockComment) {
				if (c == "*" && next == "/") {
					blockComment = false;
					out.add("  ");
					i += 2;
				} else {
					out.add(c == "\n" || c == "\r" ? c : " ");
					i++;
				}
				continue;
			}

			if (inString) {
				out.add(c);
				if (escaped) {
					escaped = false;
				} else if (c == "\\") {
					escaped = true;
				} else if (c == "\"") {
					inString = false;
				}
				i++;
				continue;
			}

			if (c == "\"") {
				inString = true;
				out.add(c);
				i++;
				continue;
			}
			if (c == "/" && next == "/") {
				lineComment = true;
				out.add("  ");
				i += 2;
				continue;
			}
			if (c == "/" && next == "*") {
				blockComment = true;
				out.add("  ");
				i += 2;
				continue;
			}

			out.add(c);
			i++;
		}

		return out.toString();
	}

	static function removeTrailingCommas(text:String):String {
		final out = new StringBuf();
		var i = 0;
		var inString = false;
		var escaped = false;

		while (i < text.length) {
			final c = text.charAt(i);
			if (inString) {
				out.add(c);
				if (escaped) {
					escaped = false;
				} else if (c == "\\") {
					escaped = true;
				} else if (c == "\"") {
					inString = false;
				}
				i++;
				continue;
			}

			if (c == "\"") {
				inString = true;
				out.add(c);
				i++;
				continue;
			}

			if (c == ",") {
				var j = i + 1;
				while (j < text.length && isWhitespace(text.charAt(j)))
					j++;
				if (j < text.length && (text.charAt(j) == "}" || text.charAt(j) == "]")) {
					i++;
					continue;
				}
			}

			out.add(c);
			i++;
		}

		return out.toString();
	}

	static function isWhitespace(c:String):Bool {
		return c == " " || c == "\n" || c == "\r" || c == "\t";
	}
}
