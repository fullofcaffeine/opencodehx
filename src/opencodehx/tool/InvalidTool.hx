package opencodehx.tool;

import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolValidation;
import opencodehx.tool.ToolError.ToolException;

class InvalidTool {
	public static function define():ToolDef {
		return {
			id: "invalid",
			description: "Do not use",
			schema: {
				parameters: [
					{name: "tool", type: "string", required: true},
					{name: "error", type: "string", required: true},
				],
			},
			execute: execute,
		};
	}

	static function execute(args:Dynamic, ctx:ToolContext):ToolResult {
		final issues:Array<String> = [];
		final tool = ToolValidation.requireString(args, "tool", issues);
		final error = ToolValidation.requireString(args, "error", issues);
		if (issues.length > 0)
			throw new ToolException(InvalidArguments("invalid", issues));
		return {
			title: "Invalid Tool",
			output: 'The arguments provided to the tool are invalid: ${error}',
			metadata: {tool: tool},
		};
	}
}
