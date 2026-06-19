package opencodehx.provider.copilot;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import haxe.extern.EitherType;

enum CopilotChatTool {
	Function(tool:CopilotFunctionTool);
	Provider;
}

typedef CopilotFunctionTool = {
	final name:String;
	final description:Undefinable<String>;
	final inputSchema:Unknown;
}

enum CopilotChatToolChoice {
	Auto;
	None;
	Required;
	Tool(toolName:String);
}

enum CopilotPreparedToolChoiceValue {
	Mode(mode:CopilotToolChoiceMode);
	Tool(choice:CopilotOpenAIToolChoice);
}

enum abstract CopilotOpenAIToolType(String) from String to String {
	final Function = "function";
}

enum abstract CopilotToolChoiceMode(String) from String to String {
	final Auto = "auto";
	final None = "none";
	final Required = "required";
}

enum abstract CopilotToolWarningType(String) from String to String {
	final Unsupported = "unsupported";
}

typedef CopilotToolWarning = {
	final type:CopilotToolWarningType;
	final feature:String;
	@:optional var details:Undefinable<String>;
}

typedef CopilotOpenAIToolFunction = {
	final name:String;
	final description:Undefinable<String>;
	final parameters:Unknown;
}

typedef CopilotOpenAITool = {
	final type:CopilotOpenAIToolType;
	@:native("function") final fn:CopilotOpenAIToolFunction;
}

typedef CopilotOpenAIToolChoiceFunction = {
	final name:String;
}

typedef CopilotOpenAIToolChoice = {
	final type:CopilotOpenAIToolType;
	@:native("function") final fn:CopilotOpenAIToolChoiceFunction;
}

typedef CopilotPreparedToolChoice = EitherType<CopilotToolChoiceMode, CopilotOpenAIToolChoice>;

typedef CopilotPreparedTools = {
	final tools:Undefinable<Array<CopilotOpenAITool>>;
	final toolChoice:Undefinable<CopilotPreparedToolChoice>;
	final toolWarnings:Array<CopilotToolWarning>;
}

class CopilotChatTools {
	public static function prepare(?tools:Array<CopilotChatTool>, ?toolChoice:CopilotChatToolChoice):CopilotPreparedTools {
		final warnings:Array<CopilotToolWarning> = [];
		if (tools == null || tools.length == 0) {
			return {
				tools: Undefinable.absent(),
				toolChoice: Undefinable.absent(),
				toolWarnings: warnings,
			};
		}

		final openaiTools:Array<CopilotOpenAITool> = [];
		for (tool in tools) {
			switch tool {
				case Function(fn):
					openaiTools.push({
						type: CopilotOpenAIToolType.Function,
						fn: {
							name: fn.name,
							description: fn.description,
							parameters: fn.inputSchema,
						},
					});
				case Provider:
					warnings.push({
						type: CopilotToolWarningType.Unsupported,
						feature: "tool type: provider",
					});
			}
		}

		return {
			tools: openaiTools,
			toolChoice: preparedChoice(toolChoice),
			toolWarnings: warnings,
		};
	}

	static function preparedChoice(toolChoice:Null<CopilotChatToolChoice>):Undefinable<CopilotPreparedToolChoice> {
		return switch toolChoice {
			case null:
				Undefinable.absent();
			case Auto:
				CopilotToolChoiceMode.Auto;
			case None:
				CopilotToolChoiceMode.None;
			case Required:
				CopilotToolChoiceMode.Required;
			case Tool(toolName):
				namedToolChoice(toolName);
		}
	}

	public static function preparedChoiceValue(toolChoice:Null<CopilotChatToolChoice>):Null<CopilotPreparedToolChoiceValue> {
		return switch toolChoice {
			case null:
				null;
			case Auto:
				CopilotPreparedToolChoiceValue.Mode(CopilotToolChoiceMode.Auto);
			case None:
				CopilotPreparedToolChoiceValue.Mode(CopilotToolChoiceMode.None);
			case Required:
				CopilotPreparedToolChoiceValue.Mode(CopilotToolChoiceMode.Required);
			case Tool(toolName):
				CopilotPreparedToolChoiceValue.Tool(namedToolChoice(toolName));
		}
	}

	public static function namedToolChoice(toolName:String):CopilotOpenAIToolChoice {
		return {
			type: CopilotOpenAIToolType.Function,
			fn: {name: toolName},
		};
	}
}
