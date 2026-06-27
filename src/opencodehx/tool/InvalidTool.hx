package opencodehx.tool;

import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolInputDecode;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolTypes.KnownToolID;
import opencodehx.tool.ToolValidation;
import opencodehx.tool.ToolError.ToolException;

typedef InvalidToolInput = {
	final tool:String;
	final error:String;
}

class InvalidTool {
	public static function define():ToolDef {
		return ToolDefinition.typed(KnownToolID.Invalid, "Do not use", {
			parameters: [
				{name: "tool", type: "string", required: true},
				{name: "error", type: "string", required: true},
			],
		}, decode, execute);
	}

	static function decode(raw:ToolCallInput):ToolInputDecode<InvalidToolInput> {
		final issues:Array<String> = [];
		final args = ToolValidation.record(raw.unknown(), issues);
		if (args == null)
			return Invalid(issues);
		final tool = ToolValidation.requireString(args, "tool", issues);
		final error = ToolValidation.requireString(args, "error", issues);
		return ToolValidation.finish(issues, {tool: tool, error: error});
	}

	static function execute(input:InvalidToolInput, ctx:ToolContext):ToolResult {
		return {
			title: "Invalid Tool",
			output: 'The arguments provided to the tool are invalid: ${input.error}',
			metadata: {tool: input.tool},
		};
	}
}
