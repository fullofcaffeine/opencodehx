package opencodehx.smoke;

import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolError.ToolFailure;
import opencodehx.tool.ToolRegistry;
import opencodehx.tool.ToolTypes.ToolContext;

class ToolSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-tool-"));
		try {
			fixture(root);
			final registry = new ToolRegistry();
			registrySurface(registry);
			errorShapes(registry, context(root));
			globExec(registry, context(root));
			grepExec(registry, context(root));
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function fixture(root:String):Void {
		write(root, "src/a.ts", "export const needle = 1;\n");
		write(root, "src/b.txt", "needle text\n");
		write(root, "src/c.ts", "export const other = 2;\n");
	}

	static function registrySurface(registry:ToolRegistry):Void {
		eq(registry.ids().join(","), "glob,grep,invalid", "builtin ids");
		eq(registry.all().length, 3, "builtin count");
		eq(registry.all({disabled: ["grep"]}).length, 2, "filtered count");
		eq(registry.get("glob").schema.parameters[0].name, "pattern", "glob schema");
	}

	static function errorShapes(registry:ToolRegistry, ctx:ToolContext):Void {
		expectToolFailure(() -> registry.get("missing"), function(failure) {
			return switch failure {
				case UnknownTool(id): id == "missing";
				case _: false;
			}
		}, "unknown tool");

		expectToolFailure(() -> registry.get("grep", {disabled: ["grep"]}), function(failure) {
			return switch failure {
				case DisabledTool(id): id == "grep";
				case _: false;
			}
		}, "disabled tool");

		expectToolFailure(() -> registry.execute("grep", {}, ctx), function(failure) {
			return switch failure {
				case InvalidArguments(id, issues): id == "grep" && issues.join("\n").indexOf("pattern") != -1;
				case _: false;
			}
		}, "invalid args");

		final invalid = registry.execute("invalid", {tool: "grep", error: "bad pattern"}, ctx);
		eq(invalid.title, "Invalid Tool", "invalid title");
		eq(invalid.output.indexOf("bad pattern") != -1, true, "invalid output");
	}

	static function globExec(registry:ToolRegistry, ctx:ToolContext):Void {
		final result = registry.execute("glob", {pattern: "*.ts", path: "src"}, ctx);
		eq(Reflect.field(result.metadata, "count"), 2, "glob count");
		eq(result.output.indexOf("a.ts") != -1, true, "glob output a");
		eq(result.output.indexOf("b.txt") == -1, true, "glob excludes txt");

		expectToolFailure(() -> registry.execute("glob", {pattern: "*.ts", path: "src/a.ts"}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "glob" && message.indexOf("glob path must be a directory") != -1;
				case _: false;
			}
		}, "glob file path failure");
	}

	static function grepExec(registry:ToolRegistry, ctx:ToolContext):Void {
		final result = registry.execute("grep", {pattern: "needle", path: "src", include: "*.ts"}, ctx);
		eq(Reflect.field(result.metadata, "matches"), 1, "grep matches");
		eq(result.output.indexOf("Found 1 matches") != -1, true, "grep found");
		eq(result.output.indexOf("Line 1:") != -1, true, "grep line");

		final exact = registry.execute("grep", {pattern: "needle", path: "src/b.txt"}, ctx);
		eq(Reflect.field(exact.metadata, "matches"), 1, "grep exact file");

		final none = registry.execute("grep", {pattern: "definitely-not-here", path: "src"}, ctx);
		eq(none.output, "No files found", "grep no matches");
	}

	static function context(root:String):ToolContext {
		return {
			directory: root,
			worktree: root,
			sessionID: "ses_tool",
			messageID: "msg_tool",
			agent: "build",
		};
	}

	static function write(root:String, relative:String, content:String):Void {
		final path = NodePath.join(root, relative);
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, content);
	}

	static function expectToolFailure(run:() -> Void, matches:ToolFailure->Bool, label:String):Void {
		try {
			run();
		} catch (error:ToolException) {
			if (matches(error.failure))
				return;
			throw '${label}: unexpected failure ${error.message}';
		}
		throw '${label}: expected failure';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
