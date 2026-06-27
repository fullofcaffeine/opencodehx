package opencodehx.tool;

import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolInfo;
import opencodehx.tool.ToolTypes.ToolParameter;
import opencodehx.tool.ToolTypes.ToolSchema;

class ToolDefinition {
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
