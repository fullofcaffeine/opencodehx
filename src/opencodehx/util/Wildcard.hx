package opencodehx.util;

import opencodehx.host.node.NodeProcess;
import opencodehx.util.Compare.compareInt;
import opencodehx.util.Compare.compareString;

typedef WildcardRule<T> = {
	final pattern:String;
	final value:T;
}

typedef StructuredWildcardInput = {
	final head:String;
	final tail:Array<String>;
}

class Wildcard {
	public static function match(value:String, pattern:String):Bool {
		final normalizedValue = normalize(value);
		final normalizedPattern = normalize(pattern);
		final regex = new EReg("^" + escape(normalizedPattern) + "$", NodeProcess.platform() == "win32" ? "i" : "");
		return regex.match(normalizedValue);
	}

	public static function all<T>(input:String, rules:Array<WildcardRule<T>>):Null<T> {
		final sorted = sortRules(rules);
		var result:Null<T> = null;
		for (rule in sorted) {
			if (match(input, rule.pattern))
				result = rule.value;
		}
		return result;
	}

	public static function allStructured<T>(input:StructuredWildcardInput, rules:Array<WildcardRule<T>>):Null<T> {
		final sorted = sortRules(rules);
		var result:Null<T> = null;
		for (rule in sorted) {
			final parts = splitPattern(rule.pattern);
			if (parts.length == 0 || !match(input.head, parts[0]))
				continue;
			if (parts.length == 1 || matchSequence(input.tail, parts.slice(1)))
				result = rule.value;
		}
		return result;
	}

	static function escape(pattern:String):String {
		final specials = "\\.+^${}()|[]";
		final out = new StringBuf();
		for (i in 0...pattern.length) {
			final char = pattern.charAt(i);
			if (char == "*") {
				out.add(".*");
			} else if (char == "?") {
				out.add(".");
			} else {
				if (specials.indexOf(char) != -1)
					out.add("\\");
				out.add(char);
			}
		}
		final escaped = out.toString();
		return StringTools.endsWith(escaped, " .*") ? escaped.substr(0, escaped.length - 3) + "( .*)?" : escaped;
	}

	static function matchSequence(items:Array<String>, patterns:Array<String>):Bool {
		if (patterns.length == 0)
			return true;
		final pattern = patterns[0];
		final rest = patterns.slice(1);
		if (pattern == "*")
			return matchSequence(items, rest);
		for (i in 0...items.length) {
			if (match(items[i], pattern) && matchSequence(items.slice(i + 1), rest))
				return true;
		}
		return false;
	}

	static function sortRules<T>(rules:Array<WildcardRule<T>>):Array<WildcardRule<T>> {
		final sorted = rules.copy();
		sorted.sort((a, b) -> {
			final length = compareInt(a.pattern.length, b.pattern.length);
			return length != 0 ? length : compareString(a.pattern, b.pattern);
		});
		return sorted;
	}

	static function splitPattern(pattern:String):Array<String> {
		final out:Array<String> = [];
		for (part in pattern.split(" ")) {
			if (part != "")
				out.push(part);
		}
		return out;
	}

	static function normalize(value:String):String {
		return StringTools.replace(value, "\\", "/");
	}
}
