package opencodehx.smoke;

import genes.ts.Unknown;
import js.html.URL;
import js.lib.Uint8Array;
import opencodehx.provider.copilot.CopilotChatMessages;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotFileData;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptMessage;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptPart;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotToolOutput;
import opencodehx.provider.copilot.CopilotChatMessages.OpenAICompatibleContentPart;
import opencodehx.provider.copilot.CopilotChatMessages.OpenAICompatibleMessage;
import opencodehx.provider.copilot.CopilotChatMessages.OpenAICompatiblePartType;
import opencodehx.provider.copilot.CopilotChatMessages.OpenAICompatibleRole;
import opencodehx.provider.copilot.CopilotChatMessages.OpenAICompatibleToolCall;

class CopilotChatMessagesSmoke {
	public static function run():Void {
		systemMessage();
		userMessages();
		assistantMessages();
		toolMessages();
		reasoningMessages();
		fullConversation();
	}

	static function systemMessage():Void {
		final result = convert([
			CopilotPromptMessage.System("You are a helpful assistant with AGENTS.md instructions.")
		]);
		eq(result.length, 1, "system count");
		eq(result[0].role, OpenAICompatibleRole.System, "system role");
		eq(contentText(result[0]), "You are a helpful assistant with AGENTS.md instructions.", "system content");
	}

	static function userMessages():Void {
		final textOnly = convert([CopilotPromptMessage.User([CopilotPromptPart.Text("Hello")])]);
		eq(contentText(textOnly[0]), "Hello", "single user text flattened");

		final image = convert([
			CopilotPromptMessage.User([
				CopilotPromptPart.Text("Hello"),
				CopilotPromptPart.File(CopilotFileData.Base64("AAECAw=="), "image/png"),
			]),
		]);
		final imageParts = contentParts(image[0]);
		eq(imageParts.length, 2, "image parts count");
		eq(imageParts[0].type, OpenAICompatiblePartType.Text, "image text part type");
		eq(imageParts[1].type, OpenAICompatiblePartType.ImageUrl, "image url part type");
		eq(imageParts[1].image_url.url, "data:image/png;base64,AAECAw==", "base64 image url");

		final bytes = convert([
			CopilotPromptMessage.User([
				CopilotPromptPart.Text("Hi"),
				CopilotPromptPart.File(CopilotFileData.Bytes(new Uint8Array([0, 1, 2, 3])), "image/png"),
			]),
		]);
		eq(contentParts(bytes[0])[1].image_url.url, "data:image/png;base64,AAECAw==", "uint8 image url");

		final remote = convert([
			CopilotPromptMessage.User([
				CopilotPromptPart.File(CopilotFileData.RemoteUrl(new URL("https://example.com/image.jpg")), "image/*"),
			]),
		]);
		eq(contentParts(remote[0])[0].image_url.url, "https://example.com/image.jpg", "remote image url");

		final multiText = convert([
			CopilotPromptMessage.User([CopilotPromptPart.Text("Part 1"), CopilotPromptPart.Text("Part 2"),]),
		]);
		eq(contentParts(multiText[0]).length, 2, "multiple user text parts remain parts");
	}

	static function assistantMessages():Void {
		final text = convert([CopilotPromptMessage.Assistant([CopilotPromptPart.Text("Hello back!")])]);
		eq(contentText(text[0]), "Hello back!", "assistant text");
		eq(text[0].tool_calls.orNull() == null, true, "assistant no tool calls");
		eq(text[0].reasoning_text.orNull() == null, true, "assistant no reasoning text");
		eq(text[0].reasoning_opaque.orNull() == null, true, "assistant no reasoning opaque");

		final onlyTool = convert([
			CopilotPromptMessage.Assistant([
				CopilotPromptPart.ToolCall("call1", "calculator", Unknown.fromBoundary({a: 1, b: 2})),
			]),
		]);
		eq(onlyTool[0].content == null, true, "tool-only assistant null content");
		final calls = toolCalls(onlyTool[0]);
		eq(calls.length, 1, "tool-only call count");
		eq(calls[0].id, "call1", "tool id");
		eq(calls[0].fn.name, "calculator", "tool name");
		eq(calls[0].fn.arguments, "{\"a\":1,\"b\":2}", "tool arguments");

		final joined = convert([
			CopilotPromptMessage.Assistant([CopilotPromptPart.Text("First part. "), CopilotPromptPart.Text("Second part."),]),
		]);
		eq(contentText(joined[0]), "First part. Second part.", "assistant text concatenation");
	}

	static function toolMessages():Void {
		final result = convert([
			CopilotPromptMessage.Assistant([
				CopilotPromptPart.ToolCall("quux", "thwomp", Unknown.fromBoundary({foo: "bar123"})),
			]),
			CopilotPromptMessage.Tool([
				CopilotPromptPart.ToolResult("quux", "thwomp", CopilotToolOutput.JsonValue(Unknown.fromBoundary({oof: "321rab"}))),
			]),
		]);
		eq(toolCalls(result[0])[0].fn.arguments, "{\"foo\":\"bar123\"}", "assistant tool stringify");
		eq(result[1].role, OpenAICompatibleRole.Tool, "tool result role");
		eq(result[1].tool_call_id, "quux", "tool result id");
		eq(contentText(result[1]), "{\"oof\":\"321rab\"}", "tool result content");

		final textResult = convert([
			CopilotPromptMessage.Tool([
				CopilotPromptPart.ToolResult("call-1", "getWeather", CopilotToolOutput.Text("It is sunny today")),
			]),
		]);
		eq(contentText(textResult[0]), "It is sunny today", "text tool output");

		final denied = convert([
			CopilotPromptMessage.Tool([
				CopilotPromptPart.ToolResult("call-2", "bash", CopilotToolOutput.ExecutionDenied()),
				CopilotPromptPart.ToolApprovalResponse("approval-2", true),
			]),
		]);
		eq(denied.length, 1, "approval response skipped");
		eq(contentText(denied[0]), "Tool execution denied.", "execution denied fallback");

		final mixed = convert([
			CopilotPromptMessage.Assistant([
				CopilotPromptPart.Text("Checking... "),
				CopilotPromptPart.ToolCall("call1", "searchTool", Unknown.fromBoundary({
					query: "Weather"
				})),
				CopilotPromptPart.Text("Almost there..."),
				CopilotPromptPart.ToolCall("call2", "mapsTool", Unknown.fromBoundary({location: "Paris"})),
			]),
		]);
		eq(contentText(mixed[0]), "Checking... Almost there...", "text plus tool calls");
		eq(toolCalls(mixed[0]).length, 2, "multiple tool calls");
	}

	static function reasoningMessages():Void {
		final omitted = convert([
			CopilotPromptMessage.Assistant([
				CopilotPromptPart.Reasoning("Let me think about this..."),
				CopilotPromptPart.Text("The answer is 42."),
			]),
		]);
		eq(contentText(omitted[0]), "The answer is 42.", "reasoning omitted content");
		eq(omitted[0].reasoning_text.orNull() == null, true, "reasoning text requires opaque");

		final withOpaque = convert([
			CopilotPromptMessage.Assistant([
				CopilotPromptPart.Reasoning("Thinking...", {copilot: {reasoningOpaque: "opaque-signature-123"}}),
				CopilotPromptPart.Text("Done!"),
			]),
		]);
		eq(withOpaque[0].reasoning_text.orNull(), "Thinking...", "reasoning text included");
		eq(withOpaque[0].reasoning_opaque.orNull(), "opaque-signature-123", "reasoning opaque included");

		final textOpaque = convert([
			CopilotPromptMessage.Assistant([
				CopilotPromptPart.Text("Done!", {copilot: {reasoningOpaque: "opaque-text-456"}}),
			]),
		]);
		eq(textOpaque[0].reasoning_opaque.orNull(), "opaque-text-456", "text part opaque");

		final reasoningOnly = convert([
			CopilotPromptMessage.Assistant([
				CopilotPromptPart.Reasoning("Just thinking, no response yet", {copilot: {reasoningOpaque: "sig-abc"}}),
			]),
		]);
		eq(reasoningOnly[0].content == null, true, "reasoning-only null content");
		eq(reasoningOnly[0].reasoning_text.orNull(), "Just thinking, no response yet", "reasoning-only text");
	}

	static function fullConversation():Void {
		final result = convert([
			CopilotPromptMessage.System("You are a helpful assistant."),
			CopilotPromptMessage.User([CopilotPromptPart.Text("What is 2+2?")]),
			CopilotPromptMessage.Assistant([
				CopilotPromptPart.Reasoning("Let me calculate 2+2...", {
					copilot: {reasoningOpaque: "sig-abc"}
				}),
				CopilotPromptPart.Text("2+2 equals 4."),
			]),
			CopilotPromptMessage.User([CopilotPromptPart.Text("What about 3+3?")]),
		]);
		eq(result.length, 4, "full conversation count");
		eq(result[0].role, OpenAICompatibleRole.System, "full system role");
		eq(result[2].reasoning_text.orNull(), "Let me calculate 2+2...", "full assistant reasoning");
		eq(result[2].reasoning_opaque.orNull(), "sig-abc", "full assistant opaque");
	}

	static function convert(prompt:Array<CopilotPromptMessage>):Array<OpenAICompatibleMessage> {
		return CopilotChatMessages.convertToOpenAICompatibleChatMessages(prompt);
	}

	static function contentText(message:OpenAICompatibleMessage):String {
		if (!Std.isOfType(message.content, String))
			throw "Expected string content";
		// Output content is `string | part[] | null`. The runtime String guard
		// narrows this smoke assertion to the string arm.
		return cast message.content;
	}

	static function contentParts(message:OpenAICompatibleMessage):Array<OpenAICompatibleContentPart> {
		if (!Std.isOfType(message.content, Array))
			throw "Expected array content";
		// Output content is `string | part[] | null`. The runtime Array guard
		// narrows this smoke assertion to the user-part array arm.
		return cast message.content;
	}

	static function toolCalls(message:OpenAICompatibleMessage):Array<OpenAICompatibleToolCall> {
		final value = message.tool_calls.orNull();
		if (value == null)
			throw "Expected tool calls";
		return value;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
