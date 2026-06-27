package opencodehx.tool;

import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolInfo;
import opencodehx.tool.ToolTypes.ToolInputDecode;
import opencodehx.tool.ToolTypes.ToolParameter;
import opencodehx.tool.ToolTypes.ToolSchema;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolError.ToolException;

class ToolDefinition {
	public static function typed<T>(id:String, description:String, schema:ToolSchema, decode:ToolCallInput->ToolInputDecode<T>,
			run:(T, ToolContext) -> ToolResult):ToolDef {
		return {
			id: id,
			description: description,
			schema: schema,
			execute: (raw, ctx) -> switch decode(raw) {
				case Decoded(input):
					run(input, ctx);
				case Invalid(issues):
					throw new ToolException(InvalidArguments(id, issues));
			},
		};
	}

	public static function fromObject(id:String, def:ToolDef):ToolInfo {
		return {
			id: id,
			init: () -> cloneDef(id, def),
		};
	}

	public static function fromFactory(id:String, init:Void->ToolDef):ToolInfo {
		return {
			id: id,
			init: init,
		};
	}

	static function cloneDef(id:String, source:ToolDef):ToolDef {
		return {
			id: id,
			description: source.description,
			schema: cloneSchema(source.schema),
			execute: source.execute,
		};
	}

	static function cloneSchema(source:ToolSchema):ToolSchema {
		return {
			parameters: [for (parameter in source.parameters) cloneParameter(parameter)],
		};
	}

	static function cloneParameter(source:ToolParameter):ToolParameter {
		return {
			name: source.name,
			type: source.type,
			required: source.required,
			description: source.description,
		};
	}
}
