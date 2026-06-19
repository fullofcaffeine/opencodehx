package opencodehx.tui;

using StringTools;

typedef TuiTranscriptRow = {
	final label:String;
	final text:String;
}

typedef TuiTextPart = {
	final text:String;
	final synthetic:Bool;
	final ignored:Bool;
}

typedef TuiToolPart = {
	final tool:String;
	final title:String;
}

enum TuiToolState {
	ToolCompleted(data:TuiToolPart);
	ToolErrored(data:TuiToolPart);
	ToolRunning(data:TuiToolPart);
}

enum TuiAssistantPart {
	AssistantText(data:TuiTextPart);
	AssistantTool(data:TuiToolState);
}

typedef TuiUserMessage = {
	final text:TuiTextPart;
}

typedef TuiAssistantMessage = {
	final mode:String;
	final modelName:String;
	final parts:Array<TuiAssistantPart>;
}

typedef TuiSessionTranscriptModel = {
	final user:TuiUserMessage;
	final assistant:TuiAssistantMessage;
}

class TuiSessionTranscript {
	public static function fakeProviderToolFixture():TuiSessionTranscriptModel {
		return {
			user: {
				text: {
					text: "Say hello from the fixture.",
					synthetic: false,
					ignored: false,
				},
			},
			assistant: {
				mode: "primary",
				modelName: "Test Model",
				parts: [
					AssistantTool(ToolCompleted({
						tool: "fixture_lookup",
						title: "Fixture lookup",
					})),
					AssistantText({
						text: "Hello from the fake provider.",
						synthetic: false,
						ignored: false,
					}),
				],
			},
		};
	}

	public static function rows(model:TuiSessionTranscriptModel):Array<TuiTranscriptRow> {
		final out:Array<TuiTranscriptRow> = [];
		if (visibleText(model.user.text)) {
			out.push({
				label: "User",
				text: model.user.text.text.trim(),
			});
		}

		for (part in model.assistant.parts) {
			switch part {
				case AssistantTool(data):
					out.push({
						label: "Tool",
						text: toolSummary(data),
					});
				case AssistantText(data):
					if (visibleText(data)) {
						out.push({
							label: "Assistant",
							text: data.text.trim(),
						});
					}
			}
		}

		out.push({
			label: "Meta",
			text: '${titleCase(model.assistant.mode)} - ${model.assistant.modelName}',
		});
		return out;
	}

	static function visibleText(data:TuiTextPart):Bool {
		return !data.synthetic && !data.ignored && data.text.trim().length > 0;
	}

	static function toolSummary(state:TuiToolState):String {
		return switch state {
			case ToolCompleted(data):
				'${data.tool}: ${data.title} completed';
			case ToolErrored(data):
				'${data.tool}: ${data.title} failed';
			case ToolRunning(data):
				'${data.tool}: ${data.title} running';
		}
	}

	static function titleCase(value:String):String {
		if (value.length == 0)
			return value;
		return value.substr(0, 1).toUpperCase() + value.substr(1).toLowerCase();
	}
}
