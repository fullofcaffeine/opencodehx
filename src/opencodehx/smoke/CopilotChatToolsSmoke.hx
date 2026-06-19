package opencodehx.smoke;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import opencodehx.provider.copilot.CopilotChatTools;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatTool;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatToolChoice;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarningType;
import opencodehx.provider.copilot.CopilotChatTools.CopilotOpenAIToolType;
import opencodehx.provider.copilot.CopilotChatTools.CopilotPreparedToolChoiceValue;
import opencodehx.provider.copilot.CopilotChatTools.CopilotToolChoiceMode;

class CopilotChatToolsSmoke {
	public static function run():Void {
		emptyTools();
		functionTool();
		providerToolWarning();
		toolChoiceModes();
		namedToolChoice();
	}

	static function emptyTools():Void {
		final result = CopilotChatTools.prepare([], CopilotChatToolChoice.Required);
		absent(result.tools, "empty tools");
		absent(result.toolChoice, "empty tool choice");
		eq(result.toolWarnings.length, 0, "empty tool warnings");
	}

	static function functionTool():Void {
		final schema = weatherSchema();
		final result = CopilotChatTools.prepare([
			CopilotChatTool.Function({
				name: "get_weather",
				description: "Get the weather for a location",
				inputSchema: schema,
			}),
		]);

		final tools = present(result.tools, "formatted tools");
		eq(tools.length, 1, "formatted tool count");
		eq(tools[0].type, CopilotOpenAIToolType.Function, "formatted tool type");
		eq(tools[0].fn.name, "get_weather", "formatted tool name");
		eq(tools[0].fn.description.orNull(), "Get the weather for a location", "formatted tool description");
		eq(tools[0].fn.parameters, schema, "formatted tool schema");
		absent(result.toolChoice, "default tool choice");
		eq(result.toolWarnings.length, 0, "function tool warnings");
	}

	static function providerToolWarning():Void {
		final result = CopilotChatTools.prepare([
			CopilotChatTool.Provider,
			CopilotChatTool.Function({
				name: "read_file",
				description: Undefinable.absent(),
				inputSchema: Unknown.fromBoundary({type: "object"}),
			}),
		]);

		final tools = present(result.tools, "provider filtered tools");
		eq(tools.length, 1, "provider filtered tool count");
		eq(tools[0].fn.name, "read_file", "provider keeps function tool");
		absent(tools[0].fn.description, "absent tool description");
		eq(result.toolWarnings.length, 1, "provider warning count");
		eq(result.toolWarnings[0].type, CopilotChatWarningType.Unsupported, "provider warning type");
		eq(result.toolWarnings[0].feature, "tool type: provider", "provider warning feature");
	}

	static function toolChoiceModes():Void {
		choiceMode(CopilotChatToolChoice.Auto, CopilotToolChoiceMode.Auto, "auto choice");
		choiceMode(CopilotChatToolChoice.None, CopilotToolChoiceMode.None, "none choice");
		choiceMode(CopilotChatToolChoice.Required, CopilotToolChoiceMode.Required, "required choice");
	}

	static function namedToolChoice():Void {
		final result = CopilotChatTools.prepare([sampleTool()], CopilotChatToolChoice.Tool("get_weather"));
		present(result.toolChoice, "named tool choice");
		final value = preparedChoiceValue(CopilotChatToolChoice.Tool("get_weather"), "named tool choice value");
		final object = switch value {
			case Tool(choice):
				choice;
			case Mode(_):
				throw "named tool choice returned a string mode";
		}
		eq(object.type, CopilotOpenAIToolType.Function, "named tool choice type");
		eq(object.fn.name, "get_weather", "named tool choice name");
	}

	static function choiceMode(input:CopilotChatToolChoice, expected:CopilotToolChoiceMode, label:String):Void {
		final result = CopilotChatTools.prepare([sampleTool()], input);
		present(result.toolChoice, label);
		final value = preparedChoiceValue(input, label);
		switch value {
			case Mode(mode):
				eq(mode, expected, label);
			case Tool(_):
				throw '$label: expected string tool choice mode';
		}
	}

	static function preparedChoiceValue(input:CopilotChatToolChoice, label:String):CopilotPreparedToolChoiceValue {
		final value = CopilotChatTools.preparedChoiceValue(input);
		if (value == null)
			throw '$label: expected prepared tool choice';
		return value;
	}

	static function sampleTool():CopilotChatTool {
		return CopilotChatTool.Function({
			name: "get_weather",
			description: "Get the weather for a location",
			inputSchema: weatherSchema(),
		});
	}

	static function weatherSchema():Unknown {
		return Unknown.fromBoundary({
			type: "object",
			properties: {
				location: {type: "string"},
			},
			required: ["location"],
		});
	}

	static function absent<T>(value:Undefinable<T>, label:String):Void {
		if (value.orNull() != null)
			throw '$label: expected absent value, got ${value.orNull()}';
	}

	static function present<T>(value:Undefinable<T>, label:String):T {
		final unwrapped = value.orNull();
		if (unwrapped == null)
			throw '$label: expected present value';
		return unwrapped;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
