package opencodehx.provider.copilot;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import haxe.DynamicAccess;
import js.lib.Date;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.externs.ai.AiSdk.AiJsonValue;
import opencodehx.externs.ai.AiSdk.AiNonNullJsonValue;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedFinishReason;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedInputTokens;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedOutputTokens;
import opencodehx.provider.copilot.CopilotResponsesRequest.CopilotResponsesSummaryPart;

typedef CopilotResponsesInputTokensDetails = {
	@:optional final cached_tokens:Null<Float>;
}

typedef CopilotResponsesOutputTokensDetails = {
	@:optional final reasoning_tokens:Null<Float>;
}

typedef CopilotResponsesUsage = {
	final input_tokens:Float;
	@:optional final input_tokens_details:Null<CopilotResponsesInputTokensDetails>;
	final output_tokens:Float;
	@:optional final output_tokens_details:Null<CopilotResponsesOutputTokensDetails>;
}

typedef CopilotMappedResponsesUsage = {
	final inputTokens:CopilotMappedInputTokens;
	final outputTokens:CopilotMappedOutputTokens;
	final raw:Undefinable<CopilotResponsesUsage>;
}

typedef CopilotResponsesIncompleteDetails = {
	@:optional final reason:Null<String>;
}

typedef CopilotResponsesResponseBody = {
	final id:String;
	final created_at:Float;
	@:optional final error:Null<CopilotResponsesErrorBody>;
	final model:String;
	final output:Array<CopilotResponsesOutputItem>;
	@:optional final service_tier:Null<String>;
	@:optional final incomplete_details:Null<CopilotResponsesIncompleteDetails>;
	final usage:CopilotResponsesUsage;
}

typedef CopilotResponsesErrorBody = {
	final code:String;
	final message:String;
}

typedef CopilotResponsesOutputText = {
	final type:String;
	final text:String;
	final annotations:Array<CopilotResponsesAnnotation>;
}

typedef CopilotResponsesOutputItem = {
	final type:String;
	@:optional final role:String;
	@:optional final id:String;
	@:optional final content:Array<CopilotResponsesOutputText>;
	@:optional final call_id:String;
	@:optional final name:String;
	@:optional final arguments:String;
	@:optional final encrypted_content:Null<String>;
	@:optional final summary:Array<CopilotResponsesSummaryPart>;
	@:optional final status:String;
	@:optional final queries:Array<String>;
	@:optional final results:Null<Array<CopilotResponsesFileSearchResult>>;
	@:optional final code:String;
	@:optional final container_id:String;
	@:optional final outputs:AiJsonValue;
	@:optional final result:AiJsonValue;
	@:optional final action:AiJsonValue;
}

typedef CopilotResponsesAnnotation = {
	final type:String;
	@:optional final url:String;
	@:optional final title:String;
	@:optional final file_id:String;
	@:optional final filename:Null<String>;
	@:optional final quote:Null<String>;
}

typedef CopilotResponsesFileSearchResult = {
	final file_id:String;
	@:optional final filename:Null<String>;
	@:optional final score:Null<Float>;
	@:optional final text:Null<String>;
	@:optional final attributes:AiJsonValue;
}

enum abstract CopilotResponsesGeneratedContentType(String) from String to String {
	final Text = "text";
	final Reasoning = "reasoning";
	final ToolCall = "tool-call";
	final ToolResult = "tool-result";
	final Source = "source";
}

typedef CopilotResponsesProviderMetadata = {
	final openai:DynamicAccess<opencodehx.externs.ai.AiSdk.AiJsonValue>;
}

typedef CopilotResponsesGeneratedContent = {
	final type:CopilotResponsesGeneratedContentType;
	@:optional var id:Undefinable<String>;
	@:optional var text:Undefinable<String>;
	@:optional var toolCallId:Undefinable<String>;
	@:optional var toolName:Undefinable<String>;
	@:optional var input:Undefinable<String>;
	@:optional var result:Undefinable<AiNonNullJsonValue>;
	@:optional var providerExecuted:Undefinable<Bool>;
	@:optional var sourceType:Undefinable<String>;
	@:optional var url:Undefinable<String>;
	@:optional var title:Undefinable<String>;
	@:optional var filename:Undefinable<String>;
	@:optional var mediaType:Undefinable<String>;
	@:optional var providerMetadata:Undefinable<CopilotResponsesProviderMetadata>;
}

class CopilotResponsesCompletion {
	public static function finishReason(finishReason:Null<String>, hasFunctionCall:Bool):CopilotMappedFinishReason {
		return {
			unified: mapOpenAIResponseFinishReason(finishReason, hasFunctionCall),
			raw: stringOrAbsent(finishReason),
		};
	}

	public static function mapOpenAIResponseFinishReason(finishReason:Null<String>, hasFunctionCall:Bool):AiFinishReason {
		return switch finishReason {
			case null:
				hasFunctionCall ? AiFinishReason.ToolCalls : AiFinishReason.Stop;
			case "max_output_tokens":
				AiFinishReason.Length;
			case "content_filter":
				AiFinishReason.ContentFilter;
			case _:
				hasFunctionCall ? AiFinishReason.ToolCalls : AiFinishReason.Other;
		}
	}

	public static function content(response:CopilotResponsesResponseBody, webSearchToolName:Null<String>,
			generateId:Void->String):{content:Array<CopilotResponsesGeneratedContent>, hasFunctionCall:Bool} {
		final out:Array<CopilotResponsesGeneratedContent> = [];
		var hasFunctionCall = false;
		for (part in response.output) {
			switch part.type {
				case "reasoning":
					final summary = part.summary == null || part.summary.length == 0 ? [{type: "summary_text", text: ""}] : part.summary;
					for (item in summary) {
						out.push({
							type: CopilotResponsesGeneratedContentType.Reasoning,
							text: item.text,
							providerMetadata: openAIMetadata(part.id, part.encrypted_content),
						});
					}
				case "message":
					if (part.content != null) {
						for (item in part.content) {
							out.push({
								type: CopilotResponsesGeneratedContentType.Text,
								text: item.text,
								providerMetadata: openAIMetadata(part.id, null),
							});
							for (annotation in item.annotations)
								annotationContent(out, annotation, generateId);
						}
					}
				case "function_call":
					hasFunctionCall = true;
					out.push({
						type: CopilotResponsesGeneratedContentType.ToolCall,
						toolCallId: stringOrAbsent(part.call_id),
						toolName: stringOrAbsent(part.name),
						input: stringOrAbsent(part.arguments),
						providerMetadata: openAIMetadata(part.id, null),
					});
				case "web_search_call":
					final name = webSearchToolName == null ? "web_search" : webSearchToolName;
					final id = requiredId(part, "web search call");
					out.push({
						type: CopilotResponsesGeneratedContentType.ToolCall,
						toolCallId: id,
						toolName: name,
						input: stringifyUnknown(part.action),
						providerExecuted: true,
					});
					out.push({
						type: CopilotResponsesGeneratedContentType.ToolResult,
						toolCallId: id,
						toolName: name,
						result: AiNonNullJsonValue.fromBoundary({status: part.status}),
					});
				case "file_search_call":
					final id = requiredId(part, "file search call");
					out.push({
						type: CopilotResponsesGeneratedContentType.ToolCall,
						toolCallId: id,
						toolName: "file_search",
						input: "{}",
						providerExecuted: true,
					});
					out.push({
						type: CopilotResponsesGeneratedContentType.ToolResult,
						toolCallId: id,
						toolName: "file_search",
						result: AiNonNullJsonValue.fromBoundary({
							queries: part.queries,
							results: part.results
						}),
					});
				case "code_interpreter_call":
					final id = requiredId(part, "code interpreter call");
					out.push({
						type: CopilotResponsesGeneratedContentType.ToolCall,
						toolCallId: id,
						toolName: "code_interpreter",
						input: haxe.Json.stringify({code: part.code, containerId: part.container_id}),
						providerExecuted: true,
					});
					out.push({
						type: CopilotResponsesGeneratedContentType.ToolResult,
						toolCallId: id,
						toolName: "code_interpreter",
						result: AiNonNullJsonValue.fromBoundary({
							outputs: jsonValueOrNull(part.outputs)
						}),
					});
				case "image_generation_call":
					final id = requiredId(part, "image generation call");
					out.push({
						type: CopilotResponsesGeneratedContentType.ToolCall,
						toolCallId: id,
						toolName: "image_generation",
						input: "{}",
						providerExecuted: true,
					});
					out.push({
						type: CopilotResponsesGeneratedContentType.ToolResult,
						toolCallId: id,
						toolName: "image_generation",
						result: AiNonNullJsonValue.fromBoundary({
							result: jsonValueOrNull(part.result)
						}),
					});
				case "local_shell_call":
					out.push({
						type: CopilotResponsesGeneratedContentType.ToolCall,
						toolCallId: stringOrAbsent(part.call_id),
						toolName: "local_shell",
						input: haxe.Json.stringify({
							action: part.action
						}),
						providerMetadata: openAIMetadata(part.id, null),
					});
				case _:
			}
		}
		return {content: out, hasFunctionCall: hasFunctionCall};
	}

	public static function usage(source:CopilotResponsesUsage):CopilotMappedResponsesUsage {
		final cached = source.input_tokens_details == null ? null : source.input_tokens_details.cached_tokens;
		final reasoning = source.output_tokens_details == null ? null : source.output_tokens_details.reasoning_tokens;
		return {
			inputTokens: {
				total: source.input_tokens,
				noCache: cached == null ? Undefinable.absent() : source.input_tokens - cached,
				cacheRead: numberOrAbsent(cached),
				cacheWrite: Undefinable.absent(),
			},
			outputTokens: {
				total: source.output_tokens,
				text: Undefinable.absent(),
				reasoning: numberOrAbsent(reasoning),
			},
			raw: source,
		};
	}

	static function annotationContent(out:Array<CopilotResponsesGeneratedContent>, annotation:CopilotResponsesAnnotation, generateId:Void->String):Void {
		switch annotation.type {
			case "url_citation":
				out.push({
					type: CopilotResponsesGeneratedContentType.Source,
					sourceType: "url",
					id: generateId(),
					url: stringOrAbsent(annotation.url),
					title: stringOrAbsent(annotation.title),
				});
			case "file_citation":
				final title = annotation.quote != null ? annotation.quote : (annotation.filename != null ? annotation.filename : "Document");
				final filename = annotation.filename != null ? annotation.filename : annotation.file_id;
				out.push({
					type: CopilotResponsesGeneratedContentType.Source,
					sourceType: "document",
					id: generateId(),
					mediaType: "text/plain",
					title: stringOrAbsent(title),
					filename: stringOrAbsent(filename),
				});
			case _:
		}
	}

	static function openAIMetadata(itemId:Null<String>, encryptedContent:Null<String>):Undefinable<CopilotResponsesProviderMetadata> {
		if (itemId == null && encryptedContent == null)
			return Undefinable.absent();
		final openai = new DynamicAccess<opencodehx.externs.ai.AiSdk.AiJsonValue>();
		if (itemId != null)
			openai.set("itemId", opencodehx.externs.ai.AiSdk.AiJsonValue.fromBoundary(itemId));
		if (encryptedContent != null)
			openai.set("reasoningEncryptedContent", opencodehx.externs.ai.AiSdk.AiJsonValue.fromBoundary(encryptedContent));
		return {openai: openai};
	}

	static function requiredId(part:CopilotResponsesOutputItem, label:String):String {
		if (part.id == null)
			throw 'Missing Responses ${label} id';
		return part.id;
	}

	static function jsonValueOrNull(value:Null<AiJsonValue>):AiJsonValue {
		return value == null ? AiJsonValue.fromBoundary(null) : value;
	}

	static function stringifyUnknown(value:Null<Unknown>):String {
		if (value == null)
			return "{}";
		// Provider-executed tool payloads are owned by the remote API. We only
		// serialize the already-decoded JSON value to preserve upstream content.
		return haxe.Json.stringify(cast value);
	}

	static function stringOrAbsent(value:Null<String>):Undefinable<String> {
		return value == null ? Undefinable.absent() : value;
	}

	static function numberOrAbsent(value:Null<Float>):Undefinable<Float> {
		return value == null ? Undefinable.absent() : value;
	}
}
