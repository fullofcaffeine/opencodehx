package opencodehx.provider.copilot;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.DynamicAccess;
import haxe.Json;
import js.lib.Date;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.externs.ai.AiSdk.AiJsonObject;
import opencodehx.externs.ai.AiSdk.AiJsonValue;
import opencodehx.externs.ai.AiSdk.AiLanguageModelFinishReason;
import opencodehx.externs.ai.AiSdk.AiLanguageModelOutputTokens;
import opencodehx.externs.ai.AiSdk.AiLanguageModelUsageTokens;
import opencodehx.externs.ai.AiSdk.AiLanguageModelV3Usage;
import opencodehx.externs.ai.AiSdk.AiProviderMetadata;
import opencodehx.externs.ai.AiSdk.AiProviderStreamPart;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarning;

using StringTools;

typedef CopilotResponsesOngoingToolCall = {
	final outputIndex:Int;
	final toolName:String;
	final toolCallId:String;
}

typedef CopilotResponsesActiveReasoning = {
	final id:String;
	final encryptedContent:Null<String>;
}

typedef CopilotResponsesStreamUsageState = {
	var inputTokens:Null<Float>;
	var outputTokens:Null<Float>;
	var reasoningTokens:Null<Float>;
	var cachedInputTokens:Null<Float>;
}

/**
 * Maps OpenAI Responses SSE chunks into AI SDK stream parts.
 *
 * The raw event payload is a JSON boundary. The mapper narrows only the fields
 * it consumes and emits SDK stream-part records to callers.
 */
class CopilotResponsesStream {
	public static function collectText(rawText:String, includeRawChunks:Bool, warnings:Array<CopilotChatWarning>,
			webSearchToolName:Undefinable<String>):Array<AiProviderStreamPart> {
		final out:Array<AiProviderStreamPart> = [{type: "stream-start", warnings: responseWarnings(warnings)}];
		final ongoingTools:Array<CopilotResponsesOngoingToolCall> = [];
		final activeReasoning = new Map<Int, CopilotResponsesActiveReasoning>();
		var currentTextId:Null<String> = null;
		var responseId:Null<String> = null;
		var finishReason:AiLanguageModelFinishReason = {unified: AiFinishReason.Other, raw: Undefinable.absent()};
		final usage:CopilotResponsesStreamUsageState = {
			inputTokens: null,
			outputTokens: null,
			reasoningTokens: null,
			cachedInputTokens: null,
		};
		var hasFunctionCall = false;

		for (payload in dataPayloads(rawText)) {
			if (payload == "[DONE]")
				continue;
			try {
				final raw = Unknown.fromBoundary(Json.parse(payload));
				final value = eventRecord(raw);
				if (includeRawChunks)
					out.push({type: "raw", rawValue: raw});
				final type = stringField(value, "type");
				switch type {
					case "response.created":
						final response = objectField(value, "response");
						responseId = stringField(response, "id");
						out.push({
							type: "response-metadata",
							id: responseId,
							timestamp: new Date(numberField(response, "created_at") * 1000),
							modelId: stringField(response, "model"),
						});
					case "response.output_item.added":
						final outputIndex = intField(value, "output_index");
						final item = objectField(value, "item");
						final itemType = stringField(item, "type");
						if (itemType == "message") {
							currentTextId = stringField(item, "id");
							final textId = currentTextId;
							out.push({
								type: "text-start",
								id: textId,
								providerMetadata: metadataForItem(textId, null),
							});
						} else if (itemType == "function_call") {
							final callId = stringField(item, "call_id");
							final name = stringField(item, "name");
							ongoingTools.push({outputIndex: outputIndex, toolName: name, toolCallId: callId});
							out.push({type: "tool-input-start", id: callId, toolName: name});
						} else if (itemType == "reasoning") {
							final id = stringField(item, "id");
							final encrypted = optionalString(field(item, "encrypted_content"));
							activeReasoning.set(outputIndex, {id: id, encryptedContent: encrypted});
							out.push({
								type: "reasoning-start",
								id: '${id}:0',
								providerMetadata: metadataForItem(id, encrypted),
							});
						}
					case "response.output_text.delta":
						if (currentTextId == null) {
							currentTextId = stringField(value, "item_id");
							final startedTextId = currentTextId;
							out.push({
								type: "text-start",
								id: startedTextId,
								providerMetadata: metadataForItem(startedTextId, null),
							});
						}
						final textId = currentTextId;
						out.push({
							type: "text-delta",
							id: textId,
							delta: stringField(value, "delta"),
						});
					case "response.function_call_arguments.delta":
						final toolIndex = intField(value, "output_index");
						final call = findTool(ongoingTools, toolIndex);
						if (call != null)
							out.push({type: "tool-input-delta", id: call.toolCallId, delta: stringField(value, "delta")});
					case "response.output_item.done":
						final outputIndex = intField(value, "output_index");
						final item = objectField(value, "item");
						final itemType = stringField(item, "type");
						if (itemType == "message" && currentTextId != null) {
							out.push({type: "text-end", id: currentTextId});
							currentTextId = null;
						} else if (itemType == "function_call") {
							hasFunctionCall = true;
							final callId = stringField(item, "call_id");
							final name = stringField(item, "name");
							removeTool(ongoingTools, outputIndex);
							out.push({type: "tool-input-end", id: callId});
							out.push({
								type: "tool-call",
								toolCallId: callId,
								toolName: name,
								input: stringField(item, "arguments"),
								providerMetadata: metadataForItem(optionalString(field(item, "id")), null),
							});
						} else if (itemType == "reasoning") {
							final active = activeReasoning.get(outputIndex);
							if (active != null) {
								out.push({
									type: "reasoning-end",
									id: '${active.id}:0',
									providerMetadata: metadataForItem(active.id, optionalString(field(item, "encrypted_content"))),
								});
								activeReasoning.remove(outputIndex);
							}
						}
					case "response.reasoning_summary_text.delta":
						final active = reasoningByItem(activeReasoning, stringField(value, "item_id"));
						if (active != null) {
							out.push({
								type: "reasoning-delta",
								id: '${active.id}:${intField(value, "summary_index")}',
								delta: stringField(value, "delta"),
								providerMetadata: metadataForItem(active.id, active.encryptedContent),
							});
						}
					case "response.completed" | "response.incomplete":
						final response = objectField(value, "response");
						final incomplete = field(response, "incomplete_details");
						final rawReason = isMissing(incomplete) ? null : optionalString(field(objectValue(incomplete, "incomplete_details"), "reason"));
						finishReason = CopilotResponsesCompletion.finishReason(rawReason, hasFunctionCall);
						final rawUsage = objectField(response, "usage");
						usage.inputTokens = numberField(rawUsage, "input_tokens");
						usage.outputTokens = numberField(rawUsage, "output_tokens");
						final inputDetails = field(rawUsage, "input_tokens_details");
						if (!isMissing(inputDetails))
							usage.cachedInputTokens = optionalNumber(field(objectValue(inputDetails, "input_tokens_details"), "cached_tokens"));
						final outputDetails = field(rawUsage, "output_tokens_details");
						if (!isMissing(outputDetails))
							usage.reasoningTokens = optionalNumber(field(objectValue(outputDetails, "output_tokens_details"), "reasoning_tokens"));
					case "error":
						out.push({type: "error", error: raw});
						finishReason = {unified: AiFinishReason.Error, raw: Undefinable.absent()};
					case _:
				}
			} catch (error:Dynamic) {
				// Parse/shape errors are contained as SDK error stream parts. The
				// catch value itself is untyped because Haxe/JS catches arbitrary
				// thrown JavaScript values at this runtime boundary.
				out.push({type: "error", error: Unknown.fromBoundary(error)});
				finishReason = {unified: AiFinishReason.Error, raw: Undefinable.absent()};
			}
		}

		if (currentTextId != null)
			out.push({type: "text-end", id: currentTextId});

		out.push({
			type: "finish",
			finishReason: finishReason,
			usage: usageFromState(usage),
			providerMetadata: metadataForResponse(responseId),
		});
		return out;
	}

	static function reasoningByItem(active:Map<Int, CopilotResponsesActiveReasoning>, itemId:String):Null<CopilotResponsesActiveReasoning> {
		for (entry in active) {
			if (entry.id == itemId)
				return entry;
		}
		return null;
	}

	static function findTool(active:Array<CopilotResponsesOngoingToolCall>, outputIndex:Int):Null<CopilotResponsesOngoingToolCall> {
		for (entry in active) {
			if (entry.outputIndex == outputIndex)
				return entry;
		}
		return null;
	}

	static function removeTool(active:Array<CopilotResponsesOngoingToolCall>, outputIndex:Int):Void {
		var index = 0;
		while (index < active.length) {
			if (active[index].outputIndex == outputIndex) {
				active.splice(index, 1);
				return;
			}
			index++;
		}
	}

	static function dataPayloads(rawText:String):Array<String> {
		final out:Array<String> = [];
		for (line in rawText.split("\n")) {
			final trimmed = StringTools.trim(line);
			if (trimmed.startsWith("data:"))
				out.push(StringTools.trim(trimmed.substr("data:".length)));
		}
		return out;
	}

	static function responseWarnings(warnings:Array<CopilotChatWarning>):Array<opencodehx.externs.ai.AiSdk.AiLanguageModelWarning> {
		final out:Array<opencodehx.externs.ai.AiSdk.AiLanguageModelWarning> = [];
		for (warning in warnings) {
			out.push({
				type: opencodehx.externs.ai.AiSdk.AiLanguageModelWarningType.Unsupported,
				feature: warning.feature,
				details: warning.details == null ? Undefinable.absent() : warning.details,
			});
		}
		return out;
	}

	static function usageFromState(source:CopilotResponsesStreamUsageState):AiLanguageModelV3Usage {
		return {
			inputTokens: inputTokens(source),
			outputTokens: outputTokens(source),
			raw: AiJsonObject.fromBoundary({
				input_tokens: source.inputTokens,
				output_tokens: source.outputTokens,
				total_tokens: source.inputTokens == null || source.outputTokens == null ? null : source.inputTokens + source.outputTokens,
			}),
		};
	}

	static function inputTokens(source:CopilotResponsesStreamUsageState):AiLanguageModelUsageTokens {
		return {
			total: numberOrAbsent(source.inputTokens),
			noCache: source.inputTokens == null
			|| source.cachedInputTokens == null ? Undefinable.absent() : source.inputTokens - source.cachedInputTokens,
			cacheRead: numberOrAbsent(source.cachedInputTokens),
			cacheWrite: Undefinable.absent(),
		};
	}

	static function outputTokens(source:CopilotResponsesStreamUsageState):AiLanguageModelOutputTokens {
		return {
			total: numberOrAbsent(source.outputTokens),
			text: Undefinable.absent(),
			reasoning: numberOrAbsent(source.reasoningTokens),
		};
	}

	static function metadataForItem(itemId:Null<String>, encryptedContent:Null<String>):Undefinable<AiProviderMetadata> {
		if (itemId == null && encryptedContent == null)
			return Undefinable.absent();
		final openai = new DynamicAccess<AiJsonValue>();
		if (itemId != null)
			openai.set("itemId", AiJsonValue.fromBoundary(itemId));
		if (encryptedContent != null)
			openai.set("reasoningEncryptedContent", AiJsonValue.fromBoundary(encryptedContent));
		final out = new DynamicAccess<AiJsonObject>();
		out.set("openai", AiJsonObject.fromBoundary(openai));
		final metadata:AiProviderMetadata = out;
		return metadata;
	}

	static function metadataForResponse(responseId:Null<String>):Undefinable<AiProviderMetadata> {
		if (responseId == null)
			return Undefinable.absent();
		final openai = new DynamicAccess<AiJsonValue>();
		openai.set("responseId", AiJsonValue.fromBoundary(responseId));
		final out = new DynamicAccess<AiJsonObject>();
		out.set("openai", AiJsonObject.fromBoundary(openai));
		final metadata:AiProviderMetadata = out;
		return metadata;
	}

	static function eventRecord(value:Unknown):UnknownRecord {
		return objectValue(value, "Responses stream event");
	}

	static function objectValue(value:Unknown, label:String):UnknownRecord {
		final record = UnknownNarrow.record(value);
		if (record == null)
			throw '${label}: expected object';
		return record;
	}

	static function field(object:UnknownRecord, name:String):Unknown {
		return object.get(name);
	}

	static function objectField(object:UnknownRecord, name:String):UnknownRecord {
		final value = field(object, name);
		return objectValue(value, 'Responses stream field ${name}');
	}

	static function stringField(object:UnknownRecord, name:String):String {
		final value = field(object, name);
		final text = UnknownNarrow.string(value);
		if (text == null)
			throw 'Responses stream field ${name}: expected string';
		return text;
	}

	static function optionalString(value:Unknown):Null<String> {
		if (isMissing(value))
			return null;
		final text = UnknownNarrow.string(value);
		if (text == null)
			throw "Responses stream optional field: expected string";
		return text;
	}

	static function numberField(object:UnknownRecord, name:String):Float {
		final value = field(object, name);
		final number = UnknownNarrow.number(value);
		if (number == null)
			throw 'Responses stream field ${name}: expected number';
		return number;
	}

	static function optionalNumber(value:Unknown):Null<Float> {
		if (isMissing(value))
			return null;
		final number = UnknownNarrow.number(value);
		if (number == null)
			throw "Responses stream optional field: expected number";
		return number;
	}

	static function intField(object:UnknownRecord, name:String):Int {
		final value = numberField(object, name);
		return Std.int(value);
	}

	static function isMissing(value:Unknown):Bool {
		return UnknownNarrow.isNull(value) || UnknownNarrow.isUndefined(value);
	}

	static function stringOrAbsent(value:Null<String>):Undefinable<String> {
		return value == null ? Undefinable.absent() : value;
	}

	static function numberOrAbsent(value:Null<Float>):Undefinable<Float> {
		return value == null ? Undefinable.absent() : value;
	}
}
