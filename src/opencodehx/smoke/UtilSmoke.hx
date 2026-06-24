package opencodehx.smoke;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.DynamicAccess;
import haxe.Json;
import js.Syntax;
import js.lib.Error as JsError;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.resource.Resources;
import opencodehx.resource.Resources.ResourcePaths;
import opencodehx.host.node.NodeProcess;
import opencodehx.host.node.NodePath;
import opencodehx.util.Color;
import opencodehx.util.DataUrl;
import opencodehx.util.ErrorTools;
import opencodehx.util.Format;
import opencodehx.util.Lazy;
import opencodehx.util.ModuleResolver;
import opencodehx.util.Wildcard;
import opencodehx.util.Which;

class UtilSmoke {
	public static function run():Void {
		formatDuration();
		color();
		errorTools();
		lazy();
		dataUrl();
		wildcard();
		which();
		moduleResolver();
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

	static function color():Void {
		eq(Color.hexToAnsiBold("#FFA500"), "\x1b[38;2;255;165;0m\x1b[1m", "hex ansi bold");
		eq(Color.hexToAnsiBold(null), null, "null hex ansi bold");
		eq(Color.hexToAnsiBold(""), null, "empty hex ansi bold");
		eq(Color.hexToAnsiBold("#FFF"), null, "short hex ansi bold");
		eq(Color.hexToAnsiBold("FFA500"), null, "missing hash hex ansi bold");
		eq(Color.hexToAnsiBold("#GGGGGG"), null, "invalid hex ansi bold");
		eq(Color.hexToAnsiBold("primary"), null, "theme color is not hex ansi bold");
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

	static function wildcard():Void {
		eq(Wildcard.match("file1.txt", "file?.txt"), true, "wildcard question");
		eq(Wildcard.match("file12.txt", "file?.txt"), false, "wildcard question length");
		eq(Wildcard.match("foo+bar", "foo+bar"), true, "wildcard escapes regex plus");

		eq(Wildcard.match("ls", "ls *"), true, "wildcard command optional args");
		eq(Wildcard.match("ls -la", "ls *"), true, "wildcard command args");
		eq(Wildcard.match("ls foo bar", "ls *"), true, "wildcard command multi args");
		eq(Wildcard.match("ls", "ls*"), true, "wildcard adjacent star empty");
		eq(Wildcard.match("lstmeval", "ls*"), true, "wildcard adjacent star broad");
		eq(Wildcard.match("lstmeval", "ls *"), false, "wildcard command space protects");
		eq(Wildcard.match("git status", "git *"), true, "wildcard git status args");
		eq(Wildcard.match("git", "git *"), true, "wildcard git no args");
		eq(Wildcard.match("git commit -m foo", "git *"), true, "wildcard git commit args");

		final rules = [
			{pattern: "*", value: "deny"},
			{pattern: "git *", value: "ask"},
			{pattern: "git status", value: "allow"},
		];
		eq(Wildcard.all("git status", rules), "allow", "wildcard all most specific");
		eq(Wildcard.all("git log", rules), "ask", "wildcard all command");
		eq(Wildcard.all("echo hi", rules), "deny", "wildcard all fallback");

		final structured = [{pattern: "git *", value: "ask"}, {pattern: "git status*", value: "allow"},];
		eq(Wildcard.allStructured({head: "git", tail: ["status", "--short"]}, structured), "allow", "wildcard structured status");
		eq(Wildcard.allStructured({head: "npm", tail: ["run", "build", "--watch"]}, [{pattern: "npm run *", value: "allow"}]), "allow",
			"wildcard structured npm");
		eq(Wildcard.allStructured({head: "ls", tail: ["-la"]}, structured), null, "wildcard structured missing");

		final flagRules = [
			{pattern: "find *", value: "allow"},
			{pattern: "find * -delete*", value: "ask"},
			{pattern: "sort*", value: "allow"},
			{pattern: "sort -o *", value: "ask"},
		];
		eq(Wildcard.allStructured({head: "find", tail: ["src", "-delete"]}, flagRules), "ask", "wildcard structured delete");
		eq(Wildcard.allStructured({head: "find", tail: ["src", "-print"]}, flagRules), "allow", "wildcard structured print");
		eq(Wildcard.allStructured({head: "sort", tail: ["-o", "out.txt"]}, flagRules), "ask", "wildcard structured sort output");
		eq(Wildcard.allStructured({head: "sort", tail: ["--reverse"]}, flagRules), "allow", "wildcard structured sort reverse");

		final sedRules = [{pattern: "sed * -i*", value: "ask"}, {pattern: "sed -n*", value: "allow"},];
		eq(Wildcard.allStructured({head: "sed", tail: ["-i", "file"]}, sedRules), "ask", "wildcard structured sed in-place");
		eq(Wildcard.allStructured({head: "sed", tail: ["-i.bak", "file"]}, sedRules), "ask", "wildcard structured sed backup");
		eq(Wildcard.allStructured({head: "sed", tail: ["-n", "1p", "file"]}, sedRules), "allow", "wildcard structured sed print");
		eq(Wildcard.allStructured({head: "sed", tail: ["-i", "-n", "/./p", "myfile.txt"]}, sedRules), "ask", "wildcard structured sed mixed");

		eq(Wildcard.match("C:\\Windows\\System32\\*", "C:/Windows/System32/*"), true, "wildcard slash pattern");
		eq(Wildcard.match("C:/Windows/System32/drivers", "C:\\Windows\\System32\\*"), true, "wildcard slash value");
		if (NodeProcess.platform() == "win32") {
			eq(Wildcard.match("C:\\windows\\system32\\hosts", "C:/Windows/System32/*"), true, "wildcard windows case path");
			eq(Wildcard.match("c:/windows/system32/hosts", "C:\\Windows\\System32\\*"), true, "wildcard windows case drive");
		} else {
			eq(Wildcard.match("/users/test/file", "/Users/test/*"), false, "wildcard unix case sensitive");
		}
	}

	static function which():Void {
		eq(Which.which("opencode-missing-command-for-test"), null, "which missing command");

		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-which-"));
		try {
			final bin = NodePath.join(root, "bin");
			Fs.mkdirSync(bin, {recursive: true});
			final tool = command(bin, "tool", true);
			samePath(Which.which("tool", envPath(bin)), tool, "which path override");

			final firstDir = NodePath.join(root, "a");
			final secondDir = NodePath.join(root, "b");
			Fs.mkdirSync(firstDir, {recursive: true});
			Fs.mkdirSync(secondDir, {recursive: true});
			final first = command(firstDir, "dupe", true);
			command(secondDir, "dupe", true);
			samePath(Which.which("dupe", envPath(firstDir + pathDelimiter() + secondDir)), first, "which first path match");

			if (NodeProcess.platform() != "win32") {
				final noexec = command(bin, "noexec", false);
				eq(Fs.existsSync(noexec), true, "which noexec fixture exists");
				eq(Which.which("noexec", envPath(bin)), null, "which rejects unix noexec");
			} else {
				final pathext = NodePath.join(bin, "pathext.CMD");
				Fs.writeFileSync(pathext, "@echo off\r\n");
				samePath(Which.which("pathext", envPath(bin, ".CMD")), pathext, "which windows pathext");

				final mixed = command(bin, "mixed", true);
				final mixedEnv = new DynamicAccess<String>();
				mixedEnv.set("Path", bin);
				final pathExt = NodeProcess.envValue("PathExt");
				mixedEnv.set("PathExt", pathExt == null ? ".CMD;.EXE;.BAT;.COM" : pathExt);
				samePath(Which.which("mixed", mixedEnv), mixed, "which windows path casing");
			}
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function moduleResolver():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-module-"));
		try {
			final project = NodePath.join(root, "proj");
			final tsserver = NodePath.join(project, "node_modules/typescript/lib/tsserver.js");
			write(tsserver, "export {}\n");
			write(NodePath.join(project, "node_modules/typescript/package.json"), '{"name":"typescript"}');
			eq(ModuleResolver.resolve("typescript/lib/tsserver.js", project), tsserver, "module resolver subpath");

			final cwd = NodePath.join(project, "apps/web");
			final eslint = NodePath.join(project, "node_modules/eslint/lib/api.js");
			write(eslint, "export {}\n");
			write(NodePath.join(project, "node_modules/eslint/package.json"), '{"name":"eslint","main":"lib/api.js"}');
			write(NodePath.join(cwd, ".keep"), "");
			eq(ModuleResolver.resolve("eslint", cwd), eslint, "module resolver ancestor package");

			final leftRoot = NodePath.join(root, "a");
			final rightRoot = NodePath.join(root, "b");
			final left = NodePath.join(leftRoot, "node_modules/biome/index.js");
			final right = NodePath.join(rightRoot, "node_modules/biome/index.js");
			write(left, "export {}\n");
			write(right, "export {}\n");
			write(NodePath.join(leftRoot, "node_modules/biome/package.json"), '{"name":"biome","main":"index.js"}');
			write(NodePath.join(rightRoot, "node_modules/biome/package.json"), '{"name":"biome","main":"index.js"}');
			eq(ModuleResolver.resolve("biome", leftRoot), left, "module resolver left root");
			eq(ModuleResolver.resolve("biome", rightRoot), right, "module resolver right root");
			eq(ModuleResolver.resolve("biome", leftRoot) != ModuleResolver.resolve("biome", rightRoot), true, "module resolver roots distinct");
			eq(ModuleResolver.resolve("missing-package", root), null, "module resolver missing");
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
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

	static function command(dir:String, name:String, exec:Bool):String {
		final file = NodePath.join(dir, name + (NodeProcess.platform() == "win32" ? ".cmd" : ""));
		Fs.writeFileSync(file, NodeProcess.platform() == "win32" ? "@echo off\r\n" : "#!/bin/sh\n");
		if (NodeProcess.platform() != "win32")
			Fs.chmodSync(file, exec ? 0x1ed : 0x1a4);
		return file;
	}

	static function write(path:String, content:String):Void {
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, content);
	}

	static function envPath(path:String, ?pathExt:String):DynamicAccess<String> {
		final env = new DynamicAccess<String>();
		env.set("PATH", path);
		final ext = pathExt == null ? NodeProcess.envValue("PATHEXT") : pathExt;
		if (ext != null)
			env.set("PATHEXT", ext);
		return env;
	}

	static function samePath(actual:Null<String>, expected:String, label:String):Void {
		if (actual == null)
			throw '$label: expected ${expected}, got null';
		if (NodeProcess.platform() == "win32")
			eq(actual.toLowerCase(), expected.toLowerCase(), label);
		else
			eq(actual, expected, label);
	}

	static function pathDelimiter():String {
		return NodeProcess.platform() == "win32" ? ";" : ":";
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
