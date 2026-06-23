package opencodehx.config;

import genes.ts.Unknown;
import haxe.DynamicAccess;
import opencodehx.config.ConfigError.ConfigException;
import opencodehx.externs.node.Fs;

typedef MarkdownDocument = {
	final data:DynamicAccess<MarkdownValue>;
	final content:String;
}

typedef MarkdownFileReference = Array<String>;

// Boundary debt: frontmatter is a user-authored YAML-ish interop surface.
// Keep raw values inside ConfigMarkdown and narrow them in ConfigAgent/ConfigCommand.

typedef MarkdownValue = Unknown;

class ConfigMarkdown {
	public static function files(template:String):Array<MarkdownFileReference> {
		final out:Array<MarkdownFileReference> = [];
		var index = 0;
		while (index < template.length) {
			if (template.charAt(index) != "@") {
				index++;
				continue;
			}
			if (index > 0 && blocksFileReference(template.charAt(index - 1))) {
				index++;
				continue;
			}
			final match = readFileReference(template, index + 1);
			if (match == "") {
				index++;
				continue;
			}
			out.push(["@" + match, match]);
			index += match.length + 1;
		}
		return out;
	}

	public static function parse(path:String):MarkdownDocument {
		return parseText(Fs.readFileSync(path, "utf8"), path);
	}

	public static function parseText(text:String, source:String):MarkdownDocument {
		final normalized = StringTools.replace(text, "\r\n", "\n");
		final lines = normalized.split("\n");
		if (lines.length == 0 || StringTools.trim(lines[0]) != "---") {
			return {data: new DynamicAccess(), content: normalized};
		}

		var close = -1;
		var index = 1;
		while (index < lines.length) {
			if (StringTools.trim(lines[index]) == "---") {
				close = index;
				break;
			}
			index++;
		}
		if (close == -1)
			throw new ConfigException(JsonError(source, "Failed to parse YAML frontmatter: missing closing ---"));

		return {
			data: parseFrontmatter(lines.slice(1, close)),
			content: lines.slice(close + 1).join("\n"),
		};
	}

	static function parseFrontmatter(lines:Array<String>):DynamicAccess<MarkdownValue> {
		final data = new DynamicAccess<MarkdownValue>();
		var index = 0;
		while (index < lines.length) {
			final raw = lines[index];
			final trimmed = StringTools.trim(raw);
			if (trimmed == "" || StringTools.startsWith(trimmed, "#") || isIndented(raw)) {
				index++;
				continue;
			}

			final colon = raw.indexOf(":");
			if (colon == -1) {
				index++;
				continue;
			}

			final key = StringTools.trim(raw.substr(0, colon));
			final value = StringTools.trim(raw.substr(colon + 1));
			if (key == "") {
				index++;
				continue;
			}

			if (value == "|" || value == "|-" || value == ">" || value == ">-") {
				final block = readBlock(lines, index + 1, value == ">" || value == ">-", value == "|-" || value == ">-");
				data.set(key, Unknown.fromBoundary(block.value));
				index = block.next;
				continue;
			}

			if (value == "" && hasIndentedChild(lines, index + 1)) {
				final nested = new DynamicAccess<MarkdownValue>();
				index++;
				while (index < lines.length && isIndented(lines[index])) {
					final child = StringTools.trim(lines[index]);
					if (child != "" && !StringTools.startsWith(child, "#")) {
						final childColon = child.indexOf(":");
						if (childColon != -1) {
							final childKey = StringTools.trim(child.substr(0, childColon));
							final childValue = StringTools.trim(child.substr(childColon + 1));
							nested.set(childKey, scalar(childValue));
						}
					}
					index++;
				}
				data.set(key, Unknown.fromBoundary(nested));
				continue;
			}

			data.set(key, scalar(value));
			index++;
		}
		return data;
	}

	static function readBlock(lines:Array<String>, start:Int, fold:Bool, stripFinalNewline:Bool):{value:String, next:Int} {
		final out:Array<String> = [];
		var index = start;
		while (index < lines.length && (isIndented(lines[index]) || StringTools.trim(lines[index]) == "")) {
			out.push(unindent(lines[index]));
			index++;
		}
		var value = fold ? out.join(" ") : out.join("\n");
		if (!stripFinalNewline)
			value += "\n";
		return {value: value, next: index};
	}

	static function scalar(value:String):MarkdownValue {
		if (value == "" || value == "null" || value == "~")
			return Unknown.fromBoundary(null);
		if (value == "true")
			return Unknown.fromBoundary(true);
		if (value == "false")
			return Unknown.fromBoundary(false);
		if ((StringTools.startsWith(value, '"') && StringTools.endsWith(value, '"'))
			|| (StringTools.startsWith(value, "'") && StringTools.endsWith(value, "'")))
			return Unknown.fromBoundary(value.substr(1, value.length - 2));
		final number = Std.parseFloat(value);
		if (!Math.isNaN(number) && Std.string(number) == value)
			return Unknown.fromBoundary(number);
		return Unknown.fromBoundary(value);
	}

	static function hasIndentedChild(lines:Array<String>, index:Int):Bool {
		return index < lines.length && isIndented(lines[index]);
	}

	static function isIndented(line:String):Bool {
		return StringTools.startsWith(line, " ") || StringTools.startsWith(line, "\t");
	}

	static function unindent(line:String):String {
		if (StringTools.startsWith(line, "  "))
			return line.substr(2);
		if (StringTools.startsWith(line, "\t"))
			return line.substr(1);
		return line;
	}

	static function readFileReference(template:String, start:Int):String {
		var index = start;
		var out = "";
		if (index < template.length && template.charAt(index) == ".") {
			out += ".";
			index++;
		}
		final first = readFileReferenceSegment(template, index);
		out += first.value;
		index = first.next;
		while (index < template.length && template.charAt(index) == ".") {
			final next = readFileReferenceSegment(template, index + 1);
			if (next.value == "")
				break;
			out += "." + next.value;
			index = next.next;
		}
		return out;
	}

	static function readFileReferenceSegment(template:String, start:Int):{value:String, next:Int} {
		var index = start;
		var out = "";
		while (index < template.length) {
			final char = template.charAt(index);
			if (char == "" || StringTools.isSpace(template, index) || char == "`" || char == "," || char == ".")
				break;
			out += char;
			index++;
		}
		return {value: out, next: index};
	}

	static function blocksFileReference(char:String):Bool {
		return char == "`" || isWord(char);
	}

	static function isWord(char:String):Bool {
		final code = char.charCodeAt(0);
		return (code >= "A".code && code <= "Z".code)
			|| (code >= "a".code && code <= "z".code)
			|| (code >= "0".code && code <= "9".code)
			|| char == "_";
	}
}
