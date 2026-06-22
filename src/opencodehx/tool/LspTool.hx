package opencodehx.tool;

import genes.ts.Unknown;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodePath;
import opencodehx.lsp.LspRuntime;
import opencodehx.lsp.LspTypes.LspLocationInput;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolError.ToolFailure;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolResult;

class LspTool {
	static final OPERATIONS = [
		"goToDefinition",
		"findReferences",
		"hover",
		"documentSymbol",
		"workspaceSymbol",
		"goToImplementation",
		"prepareCallHierarchy",
		"incomingCalls",
		"outgoingCalls"
	];

	public static function define(runtime:LspRuntime):ToolDef {
		return {
			id: "lsp",
			description: "Query language server protocol features for a source file.",
			schema: {
				parameters: [
					{name: "operation", type: "string", required: true},
					{name: "filePath", type: "string", required: true},
					{name: "line", type: "number", required: true},
					{name: "character", type: "number", required: true}
				]
			},
			execute: (args, ctx) -> execute(runtime, args, ctx),
		};
	}

	static function execute(runtime:LspRuntime, args:Dynamic, ctx:ToolContext):ToolResult {
		// Tool arguments arrive from the registry's JSON/tool-call boundary.
		// Keep Dynamic local to field validation and return typed values below.
		final operation = stringField(args, "operation");
		final filePath = stringField(args, "filePath");
		final line = intField(args, "line");
		final character = intField(args, "character");
		if (OPERATIONS.indexOf(operation) == -1)
			throw new ToolException(InvalidArguments("lsp", ['operation must be one of ${OPERATIONS.join(", ")}']));
		final file = NodePath.isAbsolute(filePath) ? filePath : NodePath.join(ctx.directory, filePath);
		if (ctx.ask != null) {
			final decision = ctx.ask({
				permission: "lsp",
				patterns: ["*"],
				always: ["*"],
				metadata: {}
			});
			if (!decision.allowed)
				throw new ToolException(PermissionDenied("lsp", decision.reason == null ? "permission denied" : decision.reason));
		}
		if (!Fs.existsSync(file))
			throw new ToolException(ExecutionFailed("lsp", 'File not found: ${file}'));
		if (!runtime.hasClients(file))
			throw new ToolException(ExecutionFailed("lsp", "No LSP server available for this file type."));
		runtime.touchFile(file, true);
		final position:LspLocationInput = {file: file, line: line - 1, character: character - 1};
		final result:Array<Unknown> = switch operation {
			case "goToDefinition": runtime.definition(position);
			case "findReferences": runtime.references(position);
			case "hover": runtime.hover(position);
			case "documentSymbol": runtime.documentSymbol(Url.pathToFileURL(file).href);
			case "workspaceSymbol": runtime.workspaceSymbol("");
			case "goToImplementation": runtime.implementation(position);
			case "prepareCallHierarchy": runtime.prepareCallHierarchy(position);
			case "incomingCalls": runtime.incomingCalls(position);
			case "outgoingCalls": runtime.outgoingCalls(position);
			case _: [];
		}
		final rel = ctx.worktree == null ? NodePath.relative(ctx.directory, file) : NodePath.relative(ctx.worktree, file);
		return {
			title: '${operation} ${rel}:${line}:${character}',
			output: result.length == 0 ? 'No results found for ${operation}' : Std.string(result),
			metadata: {
				result: result
			},
		};
	}

	static function stringField(args:Dynamic, name:String):String {
		// See execute: raw field reads are contained to argument decoding.
		final value = Reflect.field(args, name);
		if (!Std.isOfType(value, String))
			throw new ToolException(InvalidArguments("lsp", ['${name} must be a string']));
		return value;
	}

	static function intField(args:Dynamic, name:String):Int {
		// See execute: raw field reads are contained to argument decoding.
		final value = Reflect.field(args, name);
		if (!Std.isOfType(value, Int))
			throw new ToolException(InvalidArguments("lsp", ['${name} must be an integer']));
		return value;
	}
}
