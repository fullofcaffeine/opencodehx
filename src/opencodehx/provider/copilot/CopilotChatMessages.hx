package opencodehx.provider.copilot;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import haxe.Json;
import haxe.extern.EitherType;
import js.html.URL;
import js.lib.Uint8Array;
import opencodehx.host.node.NodeBuffer;

using StringTools;

enum CopilotPromptMessage {
	System(content:String, ?providerOptions:CopilotProviderOptions);
	User(content:Array<CopilotPromptPart>, ?providerOptions:CopilotProviderOptions);
	Assistant(content:Array<CopilotPromptPart>, ?providerOptions:CopilotProviderOptions);
	Tool(content:Array<CopilotPromptPart>, ?providerOptions:CopilotProviderOptions);
}

enum CopilotPromptPart {
	Text(text:String, ?providerOptions:CopilotProviderOptions);
	File(data:CopilotFileData, mediaType:String, ?providerOptions:CopilotProviderOptions);
	Reasoning(text:String, ?providerOptions:CopilotProviderOptions);
	ToolCall(toolCallId:String, toolName:String, input:Unknown, ?providerOptions:CopilotProviderOptions);
	ToolResult(toolCallId:String, toolName:String, output:CopilotToolOutput, ?providerOptions:CopilotProviderOptions);
	ToolApprovalResponse(approvalId:String, approved:Bool, ?reason:String, ?providerOptions:CopilotProviderOptions);
}

enum CopilotFileData {
	Base64(value:String);
	Bytes(value:Uint8Array);
	RemoteUrl(value:URL);
}

enum CopilotToolOutput {
	Text(value:String);
	ErrorText(value:String);
	ExecutionDenied(?reason:String);
	Content(value:Unknown);
	JsonValue(value:Unknown);
	ErrorJson(value:Unknown);
}

typedef CopilotProviderOptions = {
	@:optional final copilot:CopilotMetadata;
}

typedef CopilotMetadata = {
	@:optional var reasoningOpaque:String;
	@:optional var copilot_cache_control:CopilotCacheControl;
}

typedef CopilotCacheControl = {
	final type:String;
}

enum abstract OpenAICompatibleRole(String) from String to String {
	final System = "system";
	final User = "user";
	final Assistant = "assistant";
	final Tool = "tool";
}

enum abstract OpenAICompatiblePartType(String) from String to String {
	final Text = "text";
	final ImageUrl = "image_url";
}

enum abstract OpenAICompatibleToolCallType(String) from String to String {
	final Function = "function";
}

typedef OpenAICompatibleContent = EitherType<String, Array<OpenAICompatibleContentPart>>;

typedef OpenAICompatibleContentPart = {
	final type:OpenAICompatiblePartType;
	@:optional var text:String;
	@:optional var image_url:OpenAICompatibleImageUrl;
	@:optional var reasoningOpaque:String;
	@:optional var copilot_cache_control:CopilotCacheControl;
}

typedef OpenAICompatibleImageUrl = {
	final url:String;
}

typedef OpenAICompatibleToolCall = {
	final id:String;
	final type:OpenAICompatibleToolCallType;
	@:native("function") final fn:OpenAICompatibleFunctionCall;
	@:optional var reasoningOpaque:String;
	@:optional var copilot_cache_control:CopilotCacheControl;
}

typedef OpenAICompatibleFunctionCall = {
	final name:String;
	final arguments:String;
}

typedef OpenAICompatibleMessage = {
	final role:OpenAICompatibleRole;
	var content:Null<OpenAICompatibleContent>;
	@:optional var tool_calls:Undefinable<Array<OpenAICompatibleToolCall>>;
	@:optional var reasoning_text:Undefinable<String>;
	@:optional var reasoning_opaque:Undefinable<String>;
	@:optional var tool_call_id:String;
	@:optional var reasoningOpaque:String;
	@:optional var copilot_cache_control:CopilotCacheControl;
}

class CopilotUnsupportedFunctionalityError extends haxe.Exception {
	public final functionality:String;

	public function new(functionality:String) {
		this.functionality = functionality;
		super('Unsupported functionality: ${functionality}');
	}
}

class CopilotChatMessages {
	public static function convertToOpenAICompatibleChatMessages(prompt:Array<CopilotPromptMessage>):Array<OpenAICompatibleMessage> {
		final messages:Array<OpenAICompatibleMessage> = [];
		for (message in prompt) {
			switch message {
				case System(content, providerOptions):
					final out = baseMessage(OpenAICompatibleRole.System, content);
					applyMetadata(out, providerOptions);
					messages.push(out);

				case User(content, providerOptions):
					if (content.length == 1) {
						switch content[0] {
							case Text(text, partOptions):
								final out = baseMessage(OpenAICompatibleRole.User, text);
								applyMetadata(out, partOptions);
								messages.push(out);
								continue;
							case _:
						}
					}

					final parts:Array<OpenAICompatibleContentPart> = [];
					for (part in content)
						parts.push(convertUserPart(part));
					final out = baseMessage(OpenAICompatibleRole.User, parts);
					applyMetadata(out, providerOptions);
					messages.push(out);

				case Assistant(content, providerOptions):
					messages.push(convertAssistantMessage(content, providerOptions));

				case Tool(content, _):
					for (part in content) {
						switch part {
							case ToolApprovalResponse(_, _, _, _):
								continue;
							case ToolResult(toolCallId, _, output, partOptions):
								final out = baseMessage(OpenAICompatibleRole.Tool, outputContent(output));
								out.tool_call_id = toolCallId;
								applyMetadata(out, partOptions);
								messages.push(out);
							case _:
						}
					}
			}
		}
		return messages;
	}

	static function convertUserPart(part:CopilotPromptPart):OpenAICompatibleContentPart {
		return switch part {
			case Text(text, providerOptions):
				final out:OpenAICompatibleContentPart = {type: OpenAICompatiblePartType.Text, text: text};
				applyPartMetadata(out, providerOptions);
				out;
			case File(data, mediaType, providerOptions):
				if (!mediaType.startsWith("image/"))
					throw new CopilotUnsupportedFunctionalityError('file part media type ${mediaType}');
				final out:OpenAICompatibleContentPart = {
					type: OpenAICompatiblePartType.ImageUrl,
					image_url: {url: imageUrl(data, mediaType)}
				};
				applyPartMetadata(out, providerOptions);
				out;
			case _:
				throw new CopilotUnsupportedFunctionalityError("non-user prompt part in user message");
		}
	}

	static function convertAssistantMessage(content:Array<CopilotPromptPart>, providerOptions:Null<CopilotProviderOptions>):OpenAICompatibleMessage {
		var text = "";
		var reasoningText:Null<String> = null;
		var reasoningOpaque:Null<String> = null;
		final toolCalls:Array<OpenAICompatibleToolCall> = [];

		for (part in content) {
			final partOpaque = reasoningOpaqueOf(providerOptionsOf(part));
			if (partOpaque != null && reasoningOpaque == null)
				reasoningOpaque = partOpaque;

			switch part {
				case Text(value, _):
					text += value;
				case Reasoning(value, _):
					if (value != "")
						reasoningText = value;
				case ToolCall(toolCallId, toolName, input, partOptions):
					final call:OpenAICompatibleToolCall = {
						id: toolCallId,
						type: OpenAICompatibleToolCallType.Function,
						fn: {
							name: toolName,
							arguments: stringifyUnknown(input),
						},
					};
					applyToolCallMetadata(call, partOptions);
					toolCalls.push(call);
				case _:
			}
		}

		final out = baseMessage(OpenAICompatibleRole.Assistant, text == "" ? null : text);
		out.tool_calls = toolCalls.length == 0 ? Undefinable.absent() : toolCalls;
		out.reasoning_text = reasoningOpaque == null || reasoningText == null ? Undefinable.absent() : reasoningText;
		out.reasoning_opaque = reasoningOpaque == null ? Undefinable.absent() : reasoningOpaque;
		applyMetadata(out, providerOptions);
		return out;
	}

	static function imageUrl(data:CopilotFileData, mediaType:String):String {
		return switch data {
			case Base64(value):
				'data:${normalizedImageMediaType(mediaType)};base64,${value}';
			case Bytes(value):
				'data:${normalizedImageMediaType(mediaType)};base64,${NodeBuffer.fromBytesBase64(value)}';
			case RemoteUrl(value):
				value.href;
		}
	}

	static function normalizedImageMediaType(mediaType:String):String {
		return mediaType == "image/*" ? "image/jpeg" : mediaType;
	}

	static function outputContent(output:CopilotToolOutput):String {
		return switch output {
			case Text(value) | ErrorText(value):
				value;
			case ExecutionDenied(reason):
				reason == null ? "Tool execution denied." : reason;
			case Content(value) | JsonValue(value) | ErrorJson(value):
				stringifyUnknown(value);
		}
	}

	static function providerOptionsOf(part:CopilotPromptPart):Null<CopilotProviderOptions> {
		return switch part {
			case Text(_, providerOptions) | File(_, _, providerOptions) | Reasoning(_, providerOptions) | ToolCall(_, _, _, providerOptions) |
				ToolResult(_, _, _, providerOptions) | ToolApprovalResponse(_, _, _, providerOptions):
				providerOptions;
		}
	}

	static function reasoningOpaqueOf(providerOptions:Null<CopilotProviderOptions>):Null<String> {
		final metadata = metadataOf(providerOptions);
		return metadata == null ? null : metadata.reasoningOpaque;
	}

	static function metadataOf(providerOptions:Null<CopilotProviderOptions>):Null<CopilotMetadata> {
		return providerOptions == null ? null : providerOptions.copilot;
	}

	static function baseMessage(role:OpenAICompatibleRole, content:Null<OpenAICompatibleContent>):OpenAICompatibleMessage {
		return {role: role, content: content};
	}

	static function applyMetadata(out:OpenAICompatibleMessage, providerOptions:Null<CopilotProviderOptions>):Void {
		final metadata = metadataOf(providerOptions);
		if (metadata == null)
			return;
		if (metadata.reasoningOpaque != null)
			out.reasoningOpaque = metadata.reasoningOpaque;
		if (metadata.copilot_cache_control != null)
			out.copilot_cache_control = metadata.copilot_cache_control;
	}

	static function applyPartMetadata(out:OpenAICompatibleContentPart, providerOptions:Null<CopilotProviderOptions>):Void {
		final metadata = metadataOf(providerOptions);
		if (metadata == null)
			return;
		if (metadata.reasoningOpaque != null)
			out.reasoningOpaque = metadata.reasoningOpaque;
		if (metadata.copilot_cache_control != null)
			out.copilot_cache_control = metadata.copilot_cache_control;
	}

	static function applyToolCallMetadata(out:OpenAICompatibleToolCall, providerOptions:Null<CopilotProviderOptions>):Void {
		final metadata = metadataOf(providerOptions);
		if (metadata == null)
			return;
		if (metadata.reasoningOpaque != null)
			out.reasoningOpaque = metadata.reasoningOpaque;
		if (metadata.copilot_cache_control != null)
			out.copilot_cache_control = metadata.copilot_cache_control;
	}

	static function stringifyUnknown(value:Unknown):String {
		// AI SDK tool inputs/results are arbitrary JSON-compatible runtime values.
		// `Unknown` deliberately blocks general property access; the only operation
		// this converter needs is the upstream `JSON.stringify` boundary step.
		return Json.stringify(cast value);
	}
}
