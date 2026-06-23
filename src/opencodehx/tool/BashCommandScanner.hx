package opencodehx.tool;

import genes.js.Async.await;
import js.lib.Error;
import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.treesitter.WebTreeSitter.Language;
import opencodehx.externs.treesitter.WebTreeSitter.Parser;
import opencodehx.externs.treesitter.WebTreeSitter.TreeSitterNode;
import opencodehx.file.FileSystem;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.resource.Resources;
import opencodehx.resource.Resources.ResourcePaths;

using StringTools;

typedef BashScan = {
	final patterns:Array<String>;
	final always:Array<String>;
	final externalDirs:Array<String>;
	final usedTreeSitter:Bool;
}

typedef BashCommandPart = {
	final type:String;
	final text:String;
}

private typedef ScanBuilder = {
	final patterns:Array<String>;
	final always:Array<String>;
	final externalDirs:Array<String>;
}

class BashCommandScanner {
	static final CWD = ["cd", "push-location", "set-location"];
	static final FILES = [
		"cd",
		"push-location",
		"set-location",
		"rm",
		"cp",
		"mv",
		"mkdir",
		"touch",
		"chmod",
		"chown",
		"cat",
		"get-content",
		"set-content",
		"add-content",
		"copy-item",
		"move-item",
		"remove-item",
		"new-item",
		"rename-item",
	];
	static final FLAGS = ["-destination", "-literalpath", "-path"];
	static final SWITCHES = ["-confirm", "-debug", "-force", "-nonewline", "-recurse", "-verbose", "-whatif"];

	static var ready = false;
	static var bashParser:Null<Parser> = null;
	static var powerShellParser:Null<Parser> = null;

	@:async
	public static function preload():Promise<Void> {
		if (ready)
			return;
		await(Parser.init({
			locateFile: locateTreeSitterFile,
		}));
		final bashLanguage = await(Language.load(Resources.wasm(ResourcePaths.known("wasm/tree-sitter-bash.wasm")).path));
		final powerShellLanguage = await(Language.load(Resources.wasm(ResourcePaths.known("wasm/tree-sitter-powershell.wasm")).path));
		final bash = new Parser();
		bash.setLanguage(bashLanguage);
		final powerShell = new Parser();
		powerShell.setLanguage(powerShellLanguage);
		bashParser = bash;
		powerShellParser = powerShell;
		ready = true;
	}

	public static function scan(projectRoot:String, command:String, cwd:String, ?shellPath:String, ?hostPlatform:String):BashScan {
		final platform = hostPlatform == null || hostPlatform == "" ? NodeProcess.platform() : hostPlatform;
		final shell = shellPath == null || shellPath == "" ? NodeProcess.shell() : shellPath;
		final ps = isPowerShell(shell, platform);
		if (ready) {
			final parser = ps ? powerShellParser : bashParser;
			if (parser != null) {
				final tree = parser.parse(command);
				if (tree != null)
					return collect(projectRoot, tree.rootNode, cwd, ps, shell, platform);
			}
		}
		return fallback(projectRoot, command, cwd, platform);
	}

	public static function isPreloaded():Bool {
		return ready;
	}

	static function locateTreeSitterFile(_file:String):String {
		return Resources.wasm(ResourcePaths.known("wasm/tree-sitter.wasm")).path;
	}

	static function collect(projectRoot:String, root:TreeSitterNode, cwd:String, ps:Bool, shell:String, platform:String):BashScan {
		final scan = builder();
		for (node in commands(root)) {
			final command = parts(node);
			final tokens = command.map(part -> part.text);
			final commandName = tokens.length == 0 ? null : (ps ? tokens[0].toLowerCase() : tokens[0]);

			if (commandName != null && contains(FILES, commandName)) {
				for (arg in pathArgs(command, ps)) {
					final resolved = argPath(arg, cwd, ps, shell, platform);
					if (resolved == null || containsPath(projectRoot, resolved, platform))
						continue;
					final dir = isDirectory(resolved) ? resolved : dirname(resolved, platform);
					pushUnique(scan.externalDirs, dir);
				}
			}

			if (tokens.length > 0 && (commandName == null || !contains(CWD, commandName))) {
				pushUnique(scan.patterns, source(node));
				pushUnique(scan.always, arityPrefix(tokens) + " *");
			}
		}
		return finish(scan, true);
	}

	static function parts(node:TreeSitterNode):Array<BashCommandPart> {
		final out:Array<BashCommandPart> = [];
		for (i in 0...node.childCount) {
			final child = node.child(i);
			if (child == null)
				continue;
			if (child.type == "command_elements") {
				for (j in 0...child.childCount) {
					final item = child.child(j);
					if (item == null || item.type == "command_argument_sep" || item.type == "redirection")
						continue;
					out.push({type: item.type, text: item.text});
				}
				continue;
			}
			if (contains([
				"command_name",
				"command_name_expr",
				"word",
				"string",
				"raw_string",
				"concatenation"
			], child.type))
				out.push({type: child.type, text: child.text});
		}
		return out;
	}

	static function commands(root:TreeSitterNode):Array<TreeSitterNode> {
		final out:Array<TreeSitterNode> = [];
		for (node in root.descendantsOfType("command")) {
			if (node != null)
				out.push(node);
		}
		return out;
	}

	static function source(node:TreeSitterNode):String {
		final parent = node.parent;
		final text = parent != null && parent.type == "redirected_statement" ? parent.text : node.text;
		return text.trim();
	}

	static function pathArgs(parts:Array<BashCommandPart>, ps:Bool):Array<String> {
		if (!ps) {
			final out:Array<String> = [];
			for (i in 1...parts.length) {
				final raw = parts[i].text;
				if (raw.startsWith("-"))
					continue;
				if (parts[0].text == "chmod" && raw.startsWith("+"))
					continue;
				out.push(raw);
			}
			return out;
		}

		final out:Array<String> = [];
		var want = false;
		for (part in parts.slice(1)) {
			if (want) {
				out.push(part.text);
				want = false;
				continue;
			}
			if (part.type == "command_parameter") {
				final flag = part.text.toLowerCase();
				if (contains(SWITCHES, flag))
					continue;
				want = contains(FLAGS, flag);
				continue;
			}
			out.push(part.text);
		}
		return out;
	}

	static function argPath(arg:String, cwd:String, ps:Bool, shell:String, platform:String):Null<String> {
		final text = ps ? expand(arg, cwd, shell) : home(unquote(arg));
		final file = text == "" ? null : prefix(text);
		if (file == null || isDynamicPath(file, ps))
			return null;
		final provided = ps ? provider(file) : file;
		if (provided == null)
			return null;
		return resolvePath(cwd, provided, platform);
	}

	static function expand(text:String, cwd:String, shell:String):String {
		var out = unquote(text);
		out = replaceEnvBraces(out);
		out = replaceEnvNames(out);
		out = replaceAuto(out, cwd, shell);
		return home(out);
	}

	static function replaceEnvBraces(text:String):String {
		var out = "";
		var cursor = 0;
		final lower = text.toLowerCase();
		while (cursor < text.length) {
			final start = lower.indexOf("${env:", cursor);
			if (start == -1) {
				out += text.substr(cursor);
				break;
			}
			final end = text.indexOf("}", start + 6);
			if (end == -1) {
				out += text.substr(cursor);
				break;
			}
			out += text.substr(cursor, start - cursor);
			final value = NodeProcess.envValue(text.substr(start + 6, end - start - 6));
			out += value == null ? "" : value;
			cursor = end + 1;
		}
		return out;
	}

	static function replaceEnvNames(text:String):String {
		var out = "";
		var cursor = 0;
		final lower = text.toLowerCase();
		while (cursor < text.length) {
			final start = lower.indexOf("$env:", cursor);
			if (start == -1) {
				out += text.substr(cursor);
				break;
			}
			var end = start + 5;
			while (end < text.length && isIdentPart(text.charAt(end)))
				end++;
			if (end == start + 5) {
				out += text.substr(cursor, end - cursor);
				cursor = end;
				continue;
			}
			out += text.substr(cursor, start - cursor);
			final value = NodeProcess.envValue(text.substr(start + 5, end - start - 5));
			out += value == null ? "" : value;
			cursor = end;
		}
		return out;
	}

	static function replaceAuto(text:String, cwd:String, shell:String):String {
		var out = "";
		var cursor = 0;
		while (cursor < text.length) {
			final start = text.indexOf("$", cursor);
			if (start == -1) {
				out += text.substr(cursor);
				break;
			}
			final replacement = autoAt(text, start, cwd, shell);
			if (replacement == null) {
				out += text.substr(cursor, start - cursor + 1);
				cursor = start + 1;
				continue;
			}
			out += text.substr(cursor, start - cursor);
			out += replacement.value;
			cursor = replacement.end;
		}
		return out;
	}

	static function autoAt(text:String, start:Int, cwd:String, shell:String):Null<{value:String, end:Int}> {
		for (name in ["PSHOME", "HOME", "PWD"]) {
			final end = start + 1 + name.length;
			if (end > text.length)
				continue;
			if (text.substr(start + 1, name.length).toUpperCase() != name)
				continue;
			if (end < text.length && text.charAt(end) != "/" && text.charAt(end) != "\\")
				continue;
			final value = switch name {
				case "HOME": Os.homedir();
				case "PWD": cwd;
				case "PSHOME": NodePath.dirname(shell);
				case _: "";
			};
			return {value: value, end: end};
		}
		return null;
	}

	static function isIdentPart(char:String):Bool {
		if (char.length == 0)
			return false;
		final code = char.charCodeAt(0);
		return (code >= "A".code && code <= "Z".code)
			|| (code >= "a".code && code <= "z".code)
			|| (code >= "0".code && code <= "9".code)
			|| char == "_";
	}

	static function unquote(text:String):String {
		if (text.length < 2)
			return text;
		final first = text.charAt(0);
		final last = text.charAt(text.length - 1);
		if ((first == '"' || first == "'") && first == last)
			return text.substr(1, text.length - 2);
		return text;
	}

	static function home(text:String):String {
		if (text == "~")
			return Os.homedir();
		if (text.startsWith("~/") || text.startsWith("~\\"))
			return NodePath.join(Os.homedir(), text.substr(2));
		return text;
	}

	static function provider(text:String):Null<String> {
		final providerSep = text.indexOf("::");
		if (providerSep > 0 && lettersOnly(text.substr(0, providerSep))) {
			if (text.substr(0, providerSep).toLowerCase() != "filesystem")
				return null;
			return text.substr(providerSep + 2);
		}
		final prefixSep = text.indexOf(":");
		if (prefixSep <= 0 || !lettersOnly(text.substr(0, prefixSep)))
			return text;
		if (prefixSep == 1)
			return text;
		return null;
	}

	static function lettersOnly(text:String):Bool {
		if (text == "")
			return false;
		for (i in 0...text.length) {
			final code = text.charCodeAt(i);
			if (!((code >= "A".code && code <= "Z".code) || (code >= "a".code && code <= "z".code)))
				return false;
		}
		return true;
	}

	static function isPowerShell(shell:String, platform:String):Bool {
		final name = NodeProcess.shellNameForPlatform(shell, platform);
		return name == "pwsh" || name == "powershell";
	}

	static function resolvePath(cwd:String, path:String, platform:String):String {
		if (platform == "win32")
			return NodePath.windowsResolve(cwd, NodeProcess.windowsPathForPlatform(path, platform));
		return NodePath.resolve(cwd, path);
	}

	static function containsPath(root:String, target:String, platform:String):Bool {
		if (platform != "win32")
			return FileSystem.contains(root, target);
		final relative = normalizeSlashes(NodePath.windowsRelative(NodePath.windowsResolve(root, "."), NodePath.windowsResolve(target, ".")));
		return relative == "" || (!relative.startsWith("..") && !NodePath.windowsIsAbsolute(relative));
	}

	static function isAbsolute(path:String, platform:String):Bool {
		return platform == "win32" ? NodePath.windowsIsAbsolute(path) : NodePath.isAbsolute(path);
	}

	static function dirname(path:String, platform:String):String {
		return platform == "win32" ? NodePath.windowsDirname(path) : NodePath.dirname(path);
	}

	static function isDirectory(path:String):Bool {
		try {
			return Fs.existsSync(path) && Fs.statSync(path).isDirectory();
		} catch (_:Error) {
			return false;
		}
	}

	static function normalizeSlashes(path:String):String {
		return path.replace("\\", "/");
	}

	static function isDynamicPath(text:String, ps:Bool):Bool {
		if (text.startsWith("(") || text.startsWith("@("))
			return true;
		if (text.indexOf("$(") != -1 || text.indexOf("${") != -1 || text.indexOf("`") != -1)
			return true;
		if (!ps)
			return text.indexOf("$") != -1;
		var index = text.indexOf("$");
		while (index != -1) {
			if (text.substr(index + 1, 4).toLowerCase() != "env:")
				return true;
			index = text.indexOf("$", index + 1);
		}
		return false;
	}

	static function prefix(text:String):Null<String> {
		var best = -1;
		for (token in ["?", "*", "["]) {
			final index = text.indexOf(token);
			if (index != -1 && (best == -1 || index < best))
				best = index;
		}
		if (best == -1)
			return text;
		return best == 0 ? null : text.substr(0, best);
	}

	static function fallback(projectRoot:String, command:String, cwd:String, platform:String):BashScan {
		final scan = builder();
		final first = firstToken(command);
		if (first != "") {
			pushUnique(scan.patterns, command);
			pushUnique(scan.always, first + " *");
		}
		if (!containsPath(projectRoot, cwd, platform))
			pushUnique(scan.externalDirs, cwd);
		for (path in likelyPathArgs(command)) {
			final absolute = isAbsolute(path, platform) ? resolvePath(path, ".", platform) : resolvePath(cwd, path, platform);
			if (!containsPath(projectRoot, absolute, platform)) {
				final dir = isDirectory(absolute) ? absolute : dirname(absolute, platform);
				pushUnique(scan.externalDirs, dir);
			}
		}
		return finish(scan, false);
	}

	static function likelyPathArgs(command:String):Array<String> {
		final tokens = shellWords(command);
		if (tokens.length == 0 || !contains(FILES, tokens[0]))
			return [];
		final paths:Array<String> = [];
		for (i in 1...tokens.length) {
			final token = tokens[i];
			if (token.startsWith("-"))
				continue;
			if (tokens[0] == "chmod" && token.startsWith("+"))
				continue;
			paths.push(token);
		}
		return paths;
	}

	static function shellWords(command:String):Array<String> {
		final words:Array<String> = [];
		var current = "";
		var quote = "";
		var i = 0;
		while (i < command.length) {
			final char = command.charAt(i);
			if (quote != "") {
				if (char == quote) {
					quote = "";
				} else {
					current += char;
				}
			} else if (char == "'" || char == '"') {
				quote = char;
			} else if (char == " " || char == "\t" || char == "\n") {
				if (current != "") {
					words.push(current);
					current = "";
				}
			} else {
				current += char;
			}
			i++;
		}
		if (current != "")
			words.push(current);
		return words;
	}

	static function firstToken(command:String):String {
		final words = shellWords(command);
		return words.length == 0 ? "" : words[0];
	}

	static function arityPrefix(tokens:Array<String>):String {
		return tokens.length == 0 ? "" : tokens[0];
	}

	static function builder():ScanBuilder {
		return {patterns: [], always: [], externalDirs: []};
	}

	static function finish(scan:ScanBuilder, usedTreeSitter:Bool):BashScan {
		return {
			patterns: scan.patterns,
			always: scan.always,
			externalDirs: scan.externalDirs,
			usedTreeSitter: usedTreeSitter,
		};
	}

	static function pushUnique(out:Array<String>, value:String):Void {
		if (out.indexOf(value) == -1)
			out.push(value);
	}

	static function contains(items:Array<String>, value:String):Bool {
		return items.indexOf(value) != -1;
	}
}
