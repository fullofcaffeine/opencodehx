package opencodehx.tool;

import genes.ts.Unknown;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodePath;
import opencodehx.lsp.LspRuntime;
import opencodehx.lsp.LspTypes.LspLocationInput;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolError.ToolFailure;
import opencodehx.tool.ToolTypes.KnownToolID;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolInputDecode;
import opencodehx.tool.ToolTypes.ToolResult;

typedef LspToolInput = {
	final operation:String;
	final filePath:String;
	final line:Int;
	final character:Int;
}

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
		return ToolDefinition.typed(KnownToolID.Lsp, "Query language server protocol features for a source file.", {
			parameters: [
				{name: "operation", type: "string", required: true},
				{name: "filePath", type: "string", required: true},
				{name: "line", type: "number", required: true},
				{name: "character", type: "number", required: true}
			]
		}, decode, (input, ctx) -> execute(runtime, input, ctx));
	}

	static function decode(raw:ToolCallInput):ToolInputDecode<LspToolInput> {
		final issues:Array<String> = [];
		final args = ToolValidation.record(raw.unknown(), issues);
		if (args == null)
			return Invalid(issues);
		final operation = ToolValidation.requireString(args, "operation", issues);
		final filePath = ToolValidation.requireString(args, "filePath", issues);
		final line = ToolValidation.requiredInt(args, "line", issues);
		final character = ToolValidation.requiredInt(args, "character", issues);
		if (issues.length == 0 && OPERATIONS.indexOf(operation) == -1)
			issues.push('operation must be one of ${OPERATIONS.join(", ")}');
		return ToolValidation.finish(issues, {
			operation: operation,
			filePath: filePath,
			line: line,
			character: character
		});
	}

	static function execute(runtime:LspRuntime, input:LspToolInput, ctx:ToolContext):ToolResult {
		if (OPERATIONS.indexOf(input.operation) == -1)
			throw new ToolException(InvalidArguments(KnownToolID.Lsp, ['operation must be one of ${OPERATIONS.join(", ")}']));
		final file = NodePath.isAbsolute(input.filePath) ? input.filePath : NodePath.join(ctx.directory, input.filePath);
		if (ctx.ask != null) {
			final decision = ctx.ask({
				permission: "lsp",
				patterns: ["*"],
				always: ["*"],
				metadata: {}
			});
			if (!decision.allowed)
				throw new ToolException(PermissionDenied(KnownToolID.Lsp, decision.reason == null ? "permission denied" : decision.reason));
		}
		if (!Fs.existsSync(file))
			throw new ToolException(ExecutionFailed(KnownToolID.Lsp, 'File not found: ${file}'));
		if (!runtime.hasClients(file))
			throw new ToolException(ExecutionFailed(KnownToolID.Lsp, "No LSP server available for this file type."));
		runtime.touchFile(file, true);
		final position:LspLocationInput = {file: file, line: input.line - 1, character: input.character - 1};
		final result:Array<Unknown> = switch input.operation {
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
			title: '${input.operation} ${rel}:${input.line}:${input.character}',
			output: result.length == 0 ? 'No results found for ${input.operation}' : Std.string(result),
			metadata: {
				result: result
			},
		};
	}
}
