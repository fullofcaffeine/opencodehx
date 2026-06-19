package opencodehx.provider.copilot;

import genes.ts.Unknown;
import haxe.extern.EitherType;
import js.html.URL;
import js.lib.Uint8Array;
import opencodehx.externs.ai.AiSdk.AiLanguageModelFileData;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPrompt;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptMessage;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptMessageContent;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptPart;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptPartType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptRole;
import opencodehx.externs.ai.AiSdk.AiLanguageModelToolResultOutput;
import opencodehx.externs.ai.AiSdk.AiProviderOptions;
import opencodehx.externs.ai.AiSdk.AiProviderOptionsMap;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotCacheControl;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotFileData;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotMetadata;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptMessage;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptPart;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotProviderOptions;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotToolOutput;

/**
 * Converts the exact AI SDK prompt union into the Haxe-owned Copilot prompt
 * model used by both chat-completions and Responses request builders.
 *
 * The AI SDK prompt type stays at the extern boundary; once converted, the
 * rest of the Copilot port can pattern-match on Haxe enums instead of probing
 * SDK discriminated-union records directly.
 */
class CopilotAiSdkPrompt {
	public static function fromSdk(prompt:AiLanguageModelPrompt):Array<CopilotPromptMessage> {
		final messages:Array<AiLanguageModelPromptMessage> = prompt;
		final out:Array<CopilotPromptMessage> = [];
		for (message in messages) {
			final providerOptions = copilotProviderOptions(message.providerOptions);
			switch message.role {
				case AiLanguageModelPromptRole.System:
					final content = textContent(message.content, "system message content");
					out.push(CopilotPromptMessage.System(content, providerOptions));
				case AiLanguageModelPromptRole.User:
					final content = partContent(message.content, "user message content");
					out.push(CopilotPromptMessage.User(promptParts(content), providerOptions));
				case AiLanguageModelPromptRole.Assistant:
					final content = partContent(message.content, "assistant message content");
					out.push(CopilotPromptMessage.Assistant(promptParts(content), providerOptions));
				case AiLanguageModelPromptRole.Tool:
					final content = partContent(message.content, "tool message content");
					out.push(CopilotPromptMessage.Tool(promptParts(content), providerOptions));
				case role:
					throw 'Unsupported AI SDK prompt role: ${role}';
			}
		}
		return out;
	}

	public static function copilotProviderOptions(source:Null<AiProviderOptions>):Null<CopilotProviderOptions> {
		if (source == null)
			return null;
		final options:AiProviderOptionsMap = source;
		final copilot = options.get("copilot");
		if (copilot == null)
			return null;
		final metadata:CopilotMetadata = {};
		if (copilot.reasoningOpaque != null)
			metadata.reasoningOpaque = copilot.reasoningOpaque;
		if (copilot.copilotCacheControl != null)
			metadata.copilot_cache_control = cacheControl(copilot.copilotCacheControl.type);
		return {copilot: metadata};
	}

	static function promptParts(parts:Array<AiLanguageModelPromptPart>):Array<CopilotPromptPart> {
		final out:Array<CopilotPromptPart> = [];
		for (part in parts)
			out.push(promptPart(part));
		return out;
	}

	static function textContent(value:AiLanguageModelPromptMessageContent, label:String):String {
		if (!Std.isOfType(value, String))
			throw 'Expected AI SDK ${label} to be a string';
		final text:String = value;
		return text;
	}

	static function partContent(value:AiLanguageModelPromptMessageContent, label:String):Array<AiLanguageModelPromptPart> {
		if (!Std.isOfType(value, Array))
			throw 'Expected AI SDK ${label} to be a part array';
		final parts:Array<AiLanguageModelPromptPart> = value;
		return parts;
	}

	static function promptPart(part:AiLanguageModelPromptPart):CopilotPromptPart {
		final providerOptions = copilotProviderOptions(part.providerOptions);
		return switch part.type {
			case AiLanguageModelPromptPartType.Text:
				CopilotPromptPart.Text(requireString(part.text, "text part text"), providerOptions);
			case AiLanguageModelPromptPartType.File:
				CopilotPromptPart.File(fileData(requireFileData(part.data, "file part data")), requireString(part.mediaType, "file part mediaType"),
					providerOptions);
			case AiLanguageModelPromptPartType.Reasoning:
				CopilotPromptPart.Reasoning(requireString(part.text, "reasoning part text"), providerOptions);
			case AiLanguageModelPromptPartType.ToolCall:
				CopilotPromptPart.ToolCall(requireString(part.toolCallId, "tool-call part toolCallId"),
					requireString(part.toolName, "tool-call part toolName"), requireUnknown(part.input, "tool-call part input"), providerOptions);
			case AiLanguageModelPromptPartType.ToolResult:
				CopilotPromptPart.ToolResult(requireString(part.toolCallId, "tool-result part toolCallId"),
					requireString(part.toolName, "tool-result part toolName"), toolOutput(requireOutput(part.output, "tool-result part output")),
					providerOptions);
			case AiLanguageModelPromptPartType.ToolApprovalResponse:
				CopilotPromptPart.ToolApprovalResponse(requireString(part.approvalId, "tool-approval-response part approvalId"),
					requireBool(part.approved, "tool-approval-response part approved"), part.reason, providerOptions);
			case type:
				throw 'Unsupported AI SDK prompt part type: ${type}';
		}
	}

	static function fileData(data:AiLanguageModelFileData):CopilotFileData {
		if (Std.isOfType(data, String)) {
			final base64Value:String = data;
			return CopilotFileData.Base64(base64Value);
		}
		if (Std.isOfType(data, Uint8Array)) {
			final bytesValue:Uint8Array = data;
			return CopilotFileData.Bytes(bytesValue);
		}
		final urlValue:URL = data;
		return CopilotFileData.RemoteUrl(urlValue);
	}

	static function toolOutput(output:AiLanguageModelToolResultOutput):CopilotToolOutput {
		return switch output.type {
			case "text":
				final value:String = requireOutputValue(output.value, "tool-result text value");
				CopilotToolOutput.Text(value);
			case "error-text":
				final value:String = requireOutputValue(output.value, "tool-result error-text value");
				CopilotToolOutput.ErrorText(value);
			case "execution-denied":
				CopilotToolOutput.ExecutionDenied(output.reason);
			case "content":
				CopilotToolOutput.Content(requireOutputUnknown(output.value, "tool-result content value"));
			case "json":
				CopilotToolOutput.JsonValue(requireOutputUnknown(output.value, "tool-result json value"));
			case "error-json":
				CopilotToolOutput.ErrorJson(requireOutputUnknown(output.value, "tool-result error-json value"));
			case type:
				throw 'Unsupported AI SDK tool-result output type: ${type}';
		}
	}

	static function cacheControl(type:String):CopilotCacheControl {
		return {type: type};
	}

	static function requireString(value:Null<String>, label:String):String {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		return value;
	}

	static function requireBool(value:Null<Bool>, label:String):Bool {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		return value;
	}

	static function requireUnknown(value:Null<Unknown>, label:String):Unknown {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		return value;
	}

	static function requireOutput(value:Null<AiLanguageModelToolResultOutput>, label:String):AiLanguageModelToolResultOutput {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		return value;
	}

	static function requireFileData(value:Null<AiLanguageModelFileData>, label:String):AiLanguageModelFileData {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		return value;
	}

	static function requireOutputValue(value:Null<EitherType<String, Unknown>>, label:String):String {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		if (!Std.isOfType(value, String))
			throw 'Expected AI SDK ${label} to be a string';
		return Std.string(value);
	}

	static function requireOutputUnknown(value:Null<EitherType<String, Unknown>>, label:String):Unknown {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		final present:Unknown = value;
		return present;
	}
}
