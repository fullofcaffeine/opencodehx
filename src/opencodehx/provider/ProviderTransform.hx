package opencodehx.provider;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderInterleavedConfig;
import opencodehx.provider.ProviderTypes.ProviderMessage;
import opencodehx.provider.ProviderTypes.ProviderMessageContent;
import opencodehx.provider.ProviderTypes.ProviderMessagePart;
import opencodehx.provider.ProviderTypes.ProviderMessagePartType;
import opencodehx.provider.ProviderTypes.ProviderMessageRole;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.provider.ProviderTypes.ProviderVariants;
import opencodehx.provider.ProviderTypes.ProviderJsonSchema;

using StringTools;

typedef ProviderTransformOptionsInput = {
	final model:ProviderModel;
	final sessionID:String;
	@:optional final providerOptions:ProviderOptions;
}

class ProviderTransform {
	public static inline final OUTPUT_TOKEN_MAX:Float = 32000;
	static final WIDELY_SUPPORTED_EFFORTS = ["low", "medium", "high"];
	static final OPENAI_EFFORTS = ["none", "minimal", "low", "medium", "high", "xhigh"];

	public static function options(input:ProviderTransformOptionsInput):ProviderOptions {
		final result = optionMap();
		final model = input.model;
		final providerID = model.providerID.toString();
		final apiID = model.api.id;
		final apiNpm = model.api.npm;
		final lowerApiID = apiID.toLowerCase();

		if (providerID == "openai" || apiNpm == "@ai-sdk/openai" || apiNpm == "@ai-sdk/github-copilot")
			result.set("store", false);

		if (apiNpm == "@ai-sdk/azure") {
			result.set("store", true);
			result.set("promptCacheKey", input.sessionID);
		}

		if (apiNpm == "@openrouter/ai-sdk-provider" || apiNpm == "@llmgateway/ai-sdk-provider") {
			result.set("usage", record1("include", true));
			if (apiID.contains("gemini-3"))
				result.set("reasoning", record1("effort", "high"));
		}

		if (providerID == "baseten" || (providerID == "opencode" && (apiID == "kimi-k2-thinking" || apiID == "glm-4.6")))
			result.set("chat_template_args", record1("enable_thinking", true));

		if ((providerID.contains("zai") || providerID.contains("zhipuai")) && apiNpm == "@ai-sdk/openai-compatible") {
			result.set("thinking", record2("type", "enabled", "clear_thinking", false));
		}

		if (providerID == "openai" || optionBool(input.providerOptions, "setCacheKey"))
			result.set("promptCacheKey", input.sessionID);

		if ((apiNpm == "@ai-sdk/google" || apiNpm == "@ai-sdk/google-vertex") && model.capabilities.reasoning) {
			final thinkingConfig = record1("includeThoughts", true);
			if (apiID.contains("gemini-3"))
				thinkingConfig.set("thinkingLevel", "high");
			result.set("thinkingConfig", thinkingConfig);
		}

		if ((apiNpm == "@ai-sdk/anthropic" || apiNpm == "@ai-sdk/google-vertex/anthropic")
			&& (lowerApiID.contains("k2p") || lowerApiID.contains("kimi-k2.") || lowerApiID.contains("kimi-k2p"))) {
			result.set("thinking", record2("type", "enabled", "budgetTokens", Math.min(16000, Math.floor(model.limit.output / 2 - 1))));
		}

		if (providerID == "alibaba-cn"
			&& model.capabilities.reasoning
			&& apiNpm == "@ai-sdk/openai-compatible"
			&& !lowerApiID.contains("kimi-k2-thinking")) {
			result.set("enable_thinking", true);
		}

		if (apiID.contains("gpt-5") && !apiID.contains("gpt-5-chat")) {
			if (!apiID.contains("gpt-5-pro")) {
				result.set("reasoningEffort", "medium");
				if (apiNpm == "@ai-sdk/openai" || apiNpm == "@ai-sdk/azure" || apiNpm == "@ai-sdk/github-copilot")
					result.set("reasoningSummary", "auto");
			}

			if (apiID.contains("gpt-5.") && !apiID.contains("codex") && !apiID.contains("-chat") && providerID != "azure")
				result.set("textVerbosity", "low");

			if (providerID.startsWith("opencode")) {
				result.set("promptCacheKey", input.sessionID);
				result.set("include", ["reasoning.encrypted_content"]);
				result.set("reasoningSummary", "auto");
			}
		}

		if (providerID == "venice")
			result.set("promptCacheKey", input.sessionID);

		if (providerID == "openrouter")
			result.set("prompt_cache_key", input.sessionID);

		if (apiNpm == "@ai-sdk/gateway")
			result.set("gateway", record1("caching", "auto"));

		return result;
	}

	public static function smallOptions(model:ProviderModel):ProviderOptions {
		final providerID = model.providerID.toString();
		final apiID = model.api.id;

		if (providerID == "openai" || model.api.npm == "@ai-sdk/openai" || model.api.npm == "@ai-sdk/github-copilot") {
			if (apiID.contains("gpt-5")) {
				final effort = apiID.contains("5.") || apiID.contains("5-mini") ? "low" : "minimal";
				return record2("store", false, "reasoningEffort", effort);
			}
			return record1("store", false);
		}

		if (providerID == "google") {
			if (apiID.contains("gemini-3"))
				return record1("thinkingConfig", record1("thinkingLevel", "minimal"));
			return record1("thinkingConfig", record1("thinkingBudget", 0));
		}

		if (providerID == "openrouter" || providerID == "llmgateway") {
			if (apiID.contains("google"))
				return record1("reasoning", record1("enabled", false));
			return record1("reasoningEffort", "minimal");
		}

		if (providerID == "venice")
			return record1("veniceParameters", record1("disableThinking", true));

		return optionMap();
	}

	public static function providerOptions(model:ProviderModel, options:ProviderOptions):ProviderOptions {
		if (model.api.npm == "@ai-sdk/gateway")
			return gatewayProviderOptions(model, options);

		final key = sdkKey(model.api.npm);
		if (model.api.npm == "@ai-sdk/azure") {
			final result = optionMap();
			result.set("openai", options);
			result.set("azure", options);
			return result;
		}
		return record1(key == null ? model.providerID.toString() : key, options);
	}

	public static function maxOutputTokens(model:ProviderModel):Float {
		final capped = Math.min(model.limit.output, OUTPUT_TOKEN_MAX);
		return capped == 0 ? OUTPUT_TOKEN_MAX : capped;
	}

	public static function schema(model:ProviderModel, schema:ProviderJsonSchema):ProviderJsonSchema {
		if (model.providerID.toString() == "google" || model.api.id.contains("gemini"))
			sanitizeGeminiSchema(schema);
		return schema;
	}

	public static function message(msgs:Array<ProviderMessage>, model:ProviderModel, options:ProviderOptions):Array<ProviderMessage> {
		var result = unsupportedParts(msgs, model);
		result = normalizeMessages(result, model, options);
		if (shouldApplyCaching(model))
			result = applyCaching(result, model);
		return remapMessageProviderOptions(result, model);
	}

	static function unsupportedParts(msgs:Array<ProviderMessage>, model:ProviderModel):Array<ProviderMessage> {
		final result:Array<ProviderMessage> = [];
		for (msg in msgs) {
			final parts = contentParts(msg.content);
			if (msg.role != ProviderMessageRole.User || parts == null) {
				result.push(msg);
				continue;
			}

			var changed = false;
			final mapped:Array<ProviderMessagePart> = [];
			for (part in parts) {
				final next = unsupportedPart(part, model);
				if (next != part)
					changed = true;
				mapped.push(next);
			}

			if (!changed) {
				result.push(msg);
				continue;
			}
			final out = cloneMessage(msg);
			out.content = mapped;
			result.push(out);
		}
		return result;
	}

	static function unsupportedPart(part:ProviderMessagePart, model:ProviderModel):ProviderMessagePart {
		if (part.type != ProviderMessagePartType.Image && part.type != ProviderMessagePartType.File)
			return part;

		if (part.type == ProviderMessagePartType.Image) {
			final image = part.image == null ? "" : part.image;
			if (isEmptyBase64DataUrl(image))
				return textPart("ERROR: Image file is empty or corrupted. Please provide a valid image.");
		}

		final mime = if (part.type == ProviderMessagePartType.Image) {
			final image = part.image == null ? "" : part.image;
			image.split(";")[0].replace("data:", "");
		} else {
			part.mediaType;
		}
		if (mime == null)
			return part;

		final modality = mimeToModality(mime);
		if (modality == null || supportsInputModality(model, modality))
			return part;

		final name = part.type == ProviderMessagePartType.File && part.filename != null ? '"${part.filename}"' : modality;
		return textPart('ERROR: Cannot read ${name} (this model does not support ${modality} input). Inform the user.');
	}

	static function normalizeMessages(msgs:Array<ProviderMessage>, model:ProviderModel, _options:ProviderOptions):Array<ProviderMessage> {
		var result = msgs;
		if (model.api.npm == "@ai-sdk/anthropic" || model.api.npm == "@ai-sdk/amazon-bedrock")
			result = filterEmptyAnthropicContent(result);

		if (model.api.id.contains("claude"))
			result = scrubToolCallIDs(result, id -> ~/[^a-zA-Z0-9_-]/g.replace(id, "_"));

		if (model.api.npm == "@ai-sdk/anthropic" || model.api.npm == "@ai-sdk/google-vertex/anthropic")
			result = splitAnthropicAssistantToolTails(result);

		if (isMistralModel(model))
			return normalizeMistralMessages(result);

		final field = interleavedField(model);
		if (field != null)
			return moveInterleavedReasoning(result, field);

		return result;
	}

	static function filterEmptyAnthropicContent(msgs:Array<ProviderMessage>):Array<ProviderMessage> {
		final result:Array<ProviderMessage> = [];
		for (msg in msgs) {
			final text = contentText(msg.content);
			if (text != null) {
				if (text != "")
					result.push(msg);
				continue;
			}

			final parts = contentParts(msg.content);
			if (parts == null) {
				result.push(msg);
				continue;
			}

			final filtered:Array<ProviderMessagePart> = [];
			for (part in parts) {
				if ((part.type == ProviderMessagePartType.Text || part.type == ProviderMessagePartType.Reasoning) && part.text == "")
					continue;
				filtered.push(part);
			}
			if (filtered.length == 0)
				continue;
			if (filtered.length == parts.length) {
				result.push(msg);
				continue;
			}
			final out = cloneMessage(msg);
			out.content = filtered;
			result.push(out);
		}
		return result;
	}

	static function scrubToolCallIDs(msgs:Array<ProviderMessage>, scrub:String->String):Array<ProviderMessage> {
		final result:Array<ProviderMessage> = [];
		for (msg in msgs) {
			final parts = contentParts(msg.content);
			if (parts == null || (msg.role != ProviderMessageRole.Assistant && msg.role != ProviderMessageRole.Tool)) {
				result.push(msg);
				continue;
			}

			var changed = false;
			final mapped:Array<ProviderMessagePart> = [];
			for (part in parts) {
				if (shouldScrubToolID(msg.role, part) && part.toolCallId != null) {
					final out = clonePart(part);
					out.toolCallId = scrub(part.toolCallId);
					mapped.push(out);
					changed = true;
				} else {
					mapped.push(part);
				}
			}
			if (!changed) {
				result.push(msg);
				continue;
			}
			final out = cloneMessage(msg);
			out.content = mapped;
			result.push(out);
		}
		return result;
	}

	static function splitAnthropicAssistantToolTails(msgs:Array<ProviderMessage>):Array<ProviderMessage> {
		final result:Array<ProviderMessage> = [];
		for (msg in msgs) {
			final parts = contentParts(msg.content);
			if (msg.role != ProviderMessageRole.Assistant || parts == null) {
				result.push(msg);
				continue;
			}

			final firstTool = firstPartIndex(parts, ProviderMessagePartType.ToolCall);
			if (firstTool == -1 || !hasNonToolAfter(parts, firstTool)) {
				result.push(msg);
				continue;
			}

			final nonTools:Array<ProviderMessagePart> = [];
			final tools:Array<ProviderMessagePart> = [];
			for (part in parts) {
				if (part.type == ProviderMessagePartType.ToolCall)
					tools.push(part);
				else
					nonTools.push(part);
			}

			final textMessage = cloneMessage(msg);
			textMessage.content = nonTools;
			result.push(textMessage);
			final toolMessage = cloneMessage(msg);
			toolMessage.content = tools;
			result.push(toolMessage);
		}
		return result;
	}

	static function normalizeMistralMessages(msgs:Array<ProviderMessage>):Array<ProviderMessage> {
		final scrubbed = scrubToolCallIDs(msgs, id -> ~/[^a-zA-Z0-9]/g.replace(id, "").substr(0, 9).rpad("0", 9));
		final result:Array<ProviderMessage> = [];
		for (i in 0...scrubbed.length) {
			final msg = scrubbed[i];
			result.push(msg);
			final next = i + 1 < scrubbed.length ? scrubbed[i + 1] : null;
			if (msg.role == ProviderMessageRole.Tool && next != null && next.role == ProviderMessageRole.User)
				result.push({role: ProviderMessageRole.Assistant, content: [textPart("Done.")]});
		}
		return result;
	}

	static function moveInterleavedReasoning(msgs:Array<ProviderMessage>, field:String):Array<ProviderMessage> {
		final result:Array<ProviderMessage> = [];
		for (msg in msgs) {
			final parts = contentParts(msg.content);
			if (msg.role != ProviderMessageRole.Assistant || parts == null) {
				result.push(msg);
				continue;
			}

			var reasoningText = "";
			final filtered:Array<ProviderMessagePart> = [];
			for (part in parts) {
				if (part.type == ProviderMessagePartType.Reasoning) {
					if (part.text != null)
						reasoningText += part.text;
				} else {
					filtered.push(part);
				}
			}

			if (filtered.length == parts.length) {
				result.push(msg);
				continue;
			}

			final out = cloneMessage(msg);
			out.content = filtered;
			if (reasoningText != "") {
				final providerOptions = cloneOptions(msg.providerOptions);
				final openaiCompatible = cloneOptionRecord(optionValue(providerOptions, "openaiCompatible"));
				openaiCompatible.set(field, reasoningText);
				providerOptions.set("openaiCompatible", openaiCompatible);
				out.providerOptions = providerOptions;
			}
			result.push(out);
		}
		return result;
	}

	static function applyCaching(msgs:Array<ProviderMessage>, model:ProviderModel):Array<ProviderMessage> {
		final selected = cacheTargetMessages(msgs);
		final cacheOptions = cacheProviderOptions();
		final result:Array<ProviderMessage> = [];
		for (msg in msgs) {
			if (selected.indexOf(msg) == -1) {
				result.push(msg);
				continue;
			}
			result.push(cacheMessage(msg, model, cacheOptions));
		}
		return result;
	}

	static function cacheMessage(msg:ProviderMessage, model:ProviderModel, cacheOptions:ProviderOptions):ProviderMessage {
		final useMessageLevelOptions = model.providerID.toString() == "anthropic"
			|| model.providerID.toString().contains("bedrock")
			|| model.api.npm == "@ai-sdk/amazon-bedrock";
		final parts = contentParts(msg.content);
		if (!useMessageLevelOptions && parts != null && parts.length > 0) {
			final last = parts[parts.length - 1];
			if (last.type != ProviderMessagePartType.ToolApprovalRequest && last.type != ProviderMessagePartType.ToolApprovalResponse) {
				final mapped = parts.copy();
				final lastCopy = clonePart(last);
				lastCopy.providerOptions = mergeProviderOptions(last.providerOptions, cacheOptions);
				mapped[parts.length - 1] = lastCopy;
				final out = cloneMessage(msg);
				out.content = mapped;
				return out;
			}
		}

		final out = cloneMessage(msg);
		out.providerOptions = mergeProviderOptions(msg.providerOptions, cacheOptions);
		return out;
	}

	static function remapMessageProviderOptions(msgs:Array<ProviderMessage>, model:ProviderModel):Array<ProviderMessage> {
		final key = sdkKey(model.api.npm);
		final providerID = model.providerID.toString();
		if (key == null || key == providerID)
			return msgs;

		final result:Array<ProviderMessage> = [];
		for (msg in msgs) {
			final remappedRoot = remapProviderOptions(msg.providerOptions, providerID, key);
			var changed = remappedRoot != msg.providerOptions;
			var nextContent = msg.content;
			final parts = contentParts(msg.content);
			if (parts != null) {
				final mapped:Array<ProviderMessagePart> = [];
				for (part in parts) {
					if (part.type == ProviderMessagePartType.ToolApprovalRequest
						|| part.type == ProviderMessagePartType.ToolApprovalResponse) {
						mapped.push(clonePart(part));
						continue;
					}
					final remappedPart = remapProviderOptions(part.providerOptions, providerID, key);
					if (remappedPart != part.providerOptions) {
						final out = clonePart(part);
						out.providerOptions = remappedPart;
						mapped.push(out);
						changed = true;
					} else {
						mapped.push(part);
					}
				}
				nextContent = mapped;
			}

			if (!changed) {
				result.push(msg);
				continue;
			}
			final out = cloneMessage(msg);
			out.content = nextContent;
			if (remappedRoot != null)
				out.providerOptions = remappedRoot;
			result.push(out);
		}
		return result;
	}

	static function isEmptyBase64DataUrl(value:String):Bool {
		if (!value.startsWith("data:"))
			return false;
		final match = ~/^data:([^;]+);base64,(.*)$/;
		return match.match(value) && match.matched(2).length == 0;
	}

	static function mimeToModality(mime:String):Null<String> {
		if (mime.startsWith("image/"))
			return "image";
		if (mime.startsWith("audio/"))
			return "audio";
		if (mime.startsWith("video/"))
			return "video";
		if (mime == "application/pdf")
			return "pdf";
		return null;
	}

	static function supportsInputModality(model:ProviderModel, modality:String):Bool {
		return switch modality {
			case "image": model.capabilities.input.image;
			case "audio": model.capabilities.input.audio;
			case "video": model.capabilities.input.video;
			case "pdf": model.capabilities.input.pdf;
			case "text": model.capabilities.input.text;
			case _: false;
		}
	}

	static function shouldScrubToolID(role:ProviderMessageRole, part:ProviderMessagePart):Bool {
		return if (role == ProviderMessageRole.Assistant) {
			part.type == ProviderMessagePartType.ToolCall
			|| part.type == ProviderMessagePartType.ToolResult;
		} else if (role == ProviderMessageRole.Tool) {
			part.type == ProviderMessagePartType.ToolResult;
		} else {
			false;
		}
	}

	static function firstPartIndex(parts:Array<ProviderMessagePart>, type:ProviderMessagePartType):Int {
		for (i in 0...parts.length) {
			if (parts[i].type == type)
				return i;
		}
		return -1;
	}

	static function hasNonToolAfter(parts:Array<ProviderMessagePart>, index:Int):Bool {
		for (i in index...parts.length) {
			if (parts[i].type != ProviderMessagePartType.ToolCall)
				return true;
		}
		return false;
	}

	static function isMistralModel(model:ProviderModel):Bool {
		final providerID = model.providerID.toString();
		final apiID = model.api.id.toLowerCase();
		return providerID == "mistral" || apiID.contains("mistral") || apiID.contains("devstral");
	}

	static function shouldApplyCaching(model:ProviderModel):Bool {
		final providerID = model.providerID.toString();
		final modelID = model.id.toString();
		final apiID = model.api.id;
		return (providerID == "anthropic"
			|| providerID == "google-vertex-anthropic"
			|| apiID.contains("anthropic")
			|| apiID.contains("claude")
			|| modelID.contains("anthropic")
			|| modelID.contains("claude")
			|| model.api.npm == "@ai-sdk/anthropic"
			|| model.api.npm == "@ai-sdk/alibaba")
			&& model.api.npm != "@ai-sdk/gateway";
	}

	static function cacheTargetMessages(msgs:Array<ProviderMessage>):Array<ProviderMessage> {
		final selected:Array<ProviderMessage> = [];
		var systemCount = 0;
		for (msg in msgs) {
			if (msg.role == ProviderMessageRole.System && systemCount < 2) {
				addUniqueMessage(selected, msg);
				systemCount++;
			}
		}

		final nonSystem:Array<ProviderMessage> = [];
		for (msg in msgs) {
			if (msg.role != ProviderMessageRole.System)
				nonSystem.push(msg);
		}
		final start = Math.floor(Math.max(0, nonSystem.length - 2));
		for (i in start...nonSystem.length)
			addUniqueMessage(selected, nonSystem[i]);

		return selected;
	}

	static function addUniqueMessage(items:Array<ProviderMessage>, msg:ProviderMessage):Void {
		if (items.indexOf(msg) == -1)
			items.push(msg);
	}

	static function cacheProviderOptions():ProviderOptions {
		final result = optionMap();
		result.set("anthropic", record1("cacheControl", record1("type", "ephemeral")));
		result.set("openrouter", record1("cacheControl", record1("type", "ephemeral")));
		result.set("bedrock", record1("cachePoint", record1("type", "default")));
		result.set("openaiCompatible", record1("cache_control", record1("type", "ephemeral")));
		result.set("copilot", record1("copilot_cache_control", record1("type", "ephemeral")));
		result.set("alibaba", record1("cacheControl", record1("type", "ephemeral")));
		return result;
	}

	static function remapProviderOptions(options:Null<ProviderOptions>, providerID:String, key:String):Null<ProviderOptions> {
		if (options == null || !options.exists(providerID))
			return options;

		final result = optionMap();
		for (field in options.keys()) {
			if (field != providerID)
				result.set(field, options.get(field));
		}
		result.set(key, options.get(providerID));
		return result;
	}

	static function mergeProviderOptions(existing:Null<ProviderOptions>, incoming:ProviderOptions):ProviderOptions {
		final result = cloneOptions(existing);
		for (key in incoming.keys()) {
			final next = optionValue(incoming, key);
			final current = optionValue(result, key);
			if (isRecord(current) && isRecord(next))
				result.set(key, mergeRecord(current, cloneOptionRecord(next)));
			else
				result.set(key, next);
		}
		return result;
	}

	static function cloneOptions(options:Null<ProviderOptions>):ProviderOptions {
		final result = optionMap();
		if (options == null)
			return result;
		for (field in options.keys())
			result.set(field, options.get(field));
		return result;
	}

	static function cloneOptionRecord(value:Unknown):ProviderOptions {
		// ProviderOptions values are SDK-owned records. This helper converts a
		// runtime-checked record into a typed option map so cache and
		// interleaved-reasoning merges do not leak unknown field reads elsewhere.
		final result = optionMap();
		final record = UnknownNarrow.record(value);
		if (record == null)
			return result;
		for (field in record.keys())
			result.set(field, record.get(field));
		return result;
	}

	static function interleavedField(model:ProviderModel):Null<String> {
		final value = model.capabilities.interleaved;
		if (Std.isOfType(value, Bool))
			return null;
		// ProviderInterleaved is an EitherType. The Bool arm is guarded above, so
		// this cast is the narrow Haxe-side access to the typed config arm.
		final config:ProviderInterleavedConfig = cast value;
		return config.field;
	}

	static function contentParts(content:ProviderMessageContent):Null<Array<ProviderMessagePart>> {
		if (!Std.isOfType(content, Array))
			return null;
		// ProviderMessageContent mirrors AI SDK's `string | part[]`. The runtime
		// Array guard proves the union arm before this localized cast.
		return cast content;
	}

	static function contentText(content:ProviderMessageContent):Null<String> {
		if (!Std.isOfType(content, String))
			return null;
		// ProviderMessageContent mirrors AI SDK's `string | part[]`. The runtime
		// String guard proves the union arm before this localized cast.
		return cast content;
	}

	static function cloneMessage(msg:ProviderMessage):ProviderMessage {
		final out:ProviderMessage = {role: msg.role, content: msg.content};
		if (msg.providerOptions != null)
			out.providerOptions = msg.providerOptions;
		return out;
	}

	static function clonePart(part:ProviderMessagePart):ProviderMessagePart {
		final out:ProviderMessagePart = {type: part.type};
		if (part.text != null)
			out.text = part.text;
		if (part.image != null)
			out.image = part.image;
		if (part.mediaType != null)
			out.mediaType = part.mediaType;
		if (part.filename != null)
			out.filename = part.filename;
		if (part.toolCallId != null)
			out.toolCallId = part.toolCallId;
		if (part.toolName != null)
			out.toolName = part.toolName;
		if (part.input != null)
			out.input = part.input;
		if (part.output != null)
			out.output = part.output;
		if (part.providerOptions != null)
			out.providerOptions = part.providerOptions;
		return out;
	}

	static function textPart(text:String):ProviderMessagePart {
		return {type: ProviderMessagePartType.Text, text: text};
	}

	public static function temperature(model:ProviderModel):Null<Float> {
		final id = model.id.toString().toLowerCase();
		if (id.contains("qwen"))
			return 0.55;
		if (id.contains("claude"))
			return null;
		if (id.contains("gemini"))
			return 1.0;
		if (id.contains("glm-4.6") || id.contains("glm-4.7"))
			return 1.0;
		if (id.contains("minimax-m2"))
			return 1.0;
		if (id.contains("kimi-k2")) {
			if (id.contains("thinking") || id.contains("k2.") || id.contains("k2p") || id.contains("k2-5"))
				return 1.0;
			return 0.6;
		}
		return null;
	}

	public static function topP(model:ProviderModel):Null<Float> {
		final id = model.id.toString().toLowerCase();
		if (id.contains("qwen"))
			return 1;
		if (id.contains("minimax-m2") || id.contains("gemini") || id.contains("kimi-k2.5") || id.contains("kimi-k2p5") || id.contains("kimi-k2-5"))
			return 0.95;
		return null;
	}

	public static function topK(model:ProviderModel):Null<Int> {
		final id = model.id.toString().toLowerCase();
		if (id.contains("minimax-m2")) {
			if (id.contains("m2.") || id.contains("m25") || id.contains("m21"))
				return 40;
			return 20;
		}
		if (id.contains("gemini"))
			return 64;
		return null;
	}

	public static function variants(model:ProviderModel):ProviderVariants {
		final result = variantMap();
		if (!model.capabilities.reasoning)
			return result;

		final id = model.id.toString().toLowerCase();
		final apiID = model.api.id.toLowerCase();
		final adaptiveEfforts = anthropicAdaptiveEfforts(model.api.id);

		if (id.contains("deepseek") || id.contains("minimax") || id.contains("glm") || id.contains("kimi") || id.contains("k2p") || id.contains("qwen")
			|| id.contains("big-pickle"))
			return result;

		if (id.contains("grok") && id.contains("grok-3-mini")) {
			if (model.api.npm == "@openrouter/ai-sdk-provider")
				return variantsFromEfforts(["low", "high"], effort -> record1("reasoning", record1("effort", effort)));
			return variantsFromEfforts(["low", "high"], effort -> record1("reasoningEffort", effort));
		}
		if (id.contains("grok"))
			return result;

		return switch model.api.npm {
			case "@openrouter/ai-sdk-provider":
				if (!id.contains("gpt") && !id.contains("gemini-3") && !id.contains("claude")) result else variantsFromEfforts(OPENAI_EFFORTS,
					effort -> record1("reasoning", record1("effort", effort)));

			case "@ai-sdk/gateway":
				gatewayVariants(model, id, adaptiveEfforts);

			case "@ai-sdk/github-copilot":
				copilotVariants(model, id);

			case "@ai-sdk/cerebras" | "@ai-sdk/togetherai" | "@ai-sdk/deepinfra" | "venice-ai-sdk-provider" | "@ai-sdk/openai-compatible" | "@ai-sdk/xai":
				variantsFromEfforts(WIDELY_SUPPORTED_EFFORTS, effort -> record1("reasoningEffort", effort));

			case "@ai-sdk/azure":
				if (id == "o1-mini") result else {
					final efforts = WIDELY_SUPPORTED_EFFORTS.copy();
					if (id.contains("gpt-5-") || id == "gpt-5")
						efforts.unshift("minimal");
					variantsFromEfforts(efforts, openAiEffortOptions);
				}

			case "@ai-sdk/openai":
				openAiVariants(model, id);

			case "@ai-sdk/anthropic" | "@ai-sdk/google-vertex/anthropic":
				anthropicVariants(model, adaptiveEfforts, true);

			case "@ai-sdk/amazon-bedrock":
				bedrockVariants(model, adaptiveEfforts);

			case "@ai-sdk/google-vertex" | "@ai-sdk/google":
				googleVariants(id);

			case "@ai-sdk/mistral":
				if (apiID.contains("mistral-small-2603")
					|| apiID.contains("mistral-small-latest")) singleVariant("high", record1("reasoningEffort", "high")) else result;

			case "@ai-sdk/cohere" | "@ai-sdk/perplexity":
				result;

			case "@ai-sdk/groq":
				variantsFromEfforts(["none", "low", "medium", "high"], effort -> record1("reasoningEffort", effort));

			case "@jerome-benoit/sap-ai-provider-v2":
				sapVariants(model, id, adaptiveEfforts);

			case _:
				result;
		}
	}

	static function sanitizeGeminiSchema(schema:ProviderJsonSchema):ProviderJsonSchema {
		sanitizeProperties(schema.properties);
		sanitizeProperties(schema.patternProperties);
		sanitizeSchemaArray(schema.prefixItems);
		sanitizeSchemaArray(schema.anyOf);
		sanitizeSchemaArray(schema.oneOf);
		sanitizeSchemaArray(schema.allOf);
		final notSchema = schema.not;
		if (notSchema != null)
			schema.not = sanitizeGeminiSchema(notSchema);
		final initialItems = schema.items;
		if (initialItems != null)
			schema.items = sanitizeGeminiSchema(initialItems);

		normalizeEnumLiterals(schema);

		final schemaProperties = schema.properties;
		final schemaRequired = schema.required;
		if (schema.type == "object" && schemaProperties != null && schemaRequired != null) {
			final filtered:Array<String> = [];
			for (field in schemaRequired) {
				if (schemaProperties.exists(field))
					filtered.push(field);
			}
			schema.required = filtered;
		}

		if (schema.type == "array" && !hasSchemaCombiner(schema)) {
			var schemaItems = schema.items;
			if (schemaItems == null) {
				schemaItems = emptySchema();
				schema.items = schemaItems;
			}
			if (!hasSchemaIntent(schemaItems))
				schemaItems.type = "string";
		}

		if (schema.type != null && schema.type != "object" && !hasSchemaCombiner(schema)) {
			deleteSchemaField(schema, "properties");
			deleteSchemaField(schema, "required");
		}

		return schema;
	}

	static function sanitizeProperties(properties:Null<haxe.DynamicAccess<ProviderJsonSchema>>):Void {
		if (properties == null)
			return;
		for (field in properties.keys())
			sanitizeProperty(properties, field);
	}

	static function sanitizeProperty(properties:haxe.DynamicAccess<ProviderJsonSchema>, field:String):Void {
		final value = properties.get(field);
		if (value != null)
			properties.set(field, sanitizeGeminiSchema(value));
	}

	static function sanitizeSchemaArray(items:Null<Array<ProviderJsonSchema>>):Void {
		if (items == null)
			return;
		for (i in 0...items.length)
			items[i] = sanitizeGeminiSchema(items[i]);
	}

	static function hasSchemaCombiner(schema:ProviderJsonSchema):Bool {
		return schema.anyOf != null || schema.oneOf != null || schema.allOf != null;
	}

	static function hasSchemaIntent(schema:ProviderJsonSchema):Bool {
		return hasSchemaCombiner(schema)
			|| schema.type != null
			|| schema.properties != null
			|| schema.patternProperties != null
			|| schema.items != null
			|| schema.prefixItems != null
			|| schema.required != null
			|| schema.not != null
			|| schema.enumValues != null
			|| Reflect.hasField(schema, "const")
			|| Reflect.hasField(schema, "$ref")
			|| Reflect.hasField(schema, "additionalProperties");
	}

	static function normalizeEnumLiterals(schema:ProviderJsonSchema):Void {
		final values = schema.enumValues;
		if (values == null)
			return;
		// JSON Schema enum values are arbitrary literals. Dynamic is isolated to
		// this normalization step, then converted to strings for Gemini's stricter
		// schema acceptance rules.
		final strings:Array<String> = [];
		for (value in values)
			strings.push(Std.string(value));
		schema.enumValues = strings;
		if (schema.type == "integer" || schema.type == "number")
			schema.type = "string";
	}

	static function deleteSchemaField(schema:ProviderJsonSchema, field:String):Void {
		// Haxe has no typed object-field delete operator. Keep Reflect.deleteField
		// confined to JSON Schema cleanup where Gemini rejects these optional
		// TypeScript object keys on non-object schema nodes.
		Reflect.deleteField(schema, field);
	}

	static function emptySchema():ProviderJsonSchema {
		return {};
	}

	static function gatewayProviderOptions(model:ProviderModel, options:ProviderOptions):ProviderOptions {
		final slug = gatewaySlug(model.api.id);
		final result = optionMap();
		final gateway = optionValue(options, "gateway");
		final rest = optionMap();
		for (key in options.keys()) {
			if (key != "gateway")
				rest.set(key, options.get(key));
		}

		if (options.exists("gateway"))
			result.set("gateway", gateway);

		if (!empty(rest)) {
			if (slug != null) {
				result.set(slug, rest);
			} else if (isRecord(gateway)) {
				result.set("gateway", mergeRecord(gateway, rest));
			} else {
				result.set("gateway", rest);
			}
		}
		return result;
	}

	static function gatewayVariants(model:ProviderModel, id:String, adaptiveEfforts:Array<String>):ProviderVariants {
		if (id.contains("anthropic")) {
			if (adaptiveEfforts.length > 0)
				return variantsFromEfforts(adaptiveEfforts, effort -> record2("thinking", record1("type", "adaptive"), "effort", effort));
			return thinkingBudgetVariants("thinking");
		}

		if (id.contains("google")) {
			if (id.contains("2.5"))
				return googleBudgetVariants();
			return variantsFromEfforts(["low", "high"], effort -> record2("includeThoughts", true, "thinkingLevel", effort));
		}

		return variantsFromEfforts(OPENAI_EFFORTS, effort -> record1("reasoningEffort", effort));
	}

	static function copilotVariants(model:ProviderModel, id:String):ProviderVariants {
		final result = variantMap();
		if (id.contains("gemini"))
			return result;
		if (id.contains("claude"))
			return variantsFromEfforts(WIDELY_SUPPORTED_EFFORTS, effort -> record1("reasoningEffort", effort));

		final efforts = WIDELY_SUPPORTED_EFFORTS.copy();
		if (id.contains("5.1-codex-max") || id.contains("5.2") || id.contains("5.3")) {
			efforts.push("xhigh");
		} else if (id.contains("gpt-5") && model.release_date >= "2025-12-04") {
			efforts.push("xhigh");
		}
		return variantsFromEfforts(efforts, openAiEffortOptions);
	}

	static function openAiVariants(model:ProviderModel, id:String):ProviderVariants {
		final result = variantMap();
		if (id == "gpt-5-pro")
			return result;

		final efforts = if (id.contains("codex")) {
			final codex = WIDELY_SUPPORTED_EFFORTS.copy();
			if (id.contains("5.2") || id.contains("5.3"))
				codex.push("xhigh");
			codex;
		} else {
			final standard = WIDELY_SUPPORTED_EFFORTS.copy();
			if (id.contains("gpt-5-") || id == "gpt-5")
				standard.unshift("minimal");
			if (model.release_date >= "2025-11-13")
				standard.unshift("none");
			if (model.release_date >= "2025-12-04")
				standard.push("xhigh");
			standard;
		};

		return variantsFromEfforts(efforts, openAiEffortOptions);
	}

	static function anthropicVariants(model:ProviderModel, adaptiveEfforts:Array<String>, includeDisplay:Bool):ProviderVariants {
		if (model.providerID.toString() == "github-copilot" && model.api.id.contains("opus-4.7"))
			return singleVariant("medium", record1("reasoningEffort", "medium"));

		if (adaptiveEfforts.length > 0) {
			final summarized = includeDisplay && (model.api.id.contains("opus-4-7") || model.api.id.contains("opus-4.7"));
			return variantsFromEfforts(adaptiveEfforts, effort -> record2("thinking", adaptiveThinking(summarized), "effort", effort));
		}

		return thinkingBudgetVariants("thinking", Math.min(16000, Math.floor(model.limit.output / 2 - 1)), Math.min(31999, model.limit.output - 1));
	}

	static function bedrockVariants(model:ProviderModel, adaptiveEfforts:Array<String>):ProviderVariants {
		if (adaptiveEfforts.length > 0) {
			final summarized = model.api.id.contains("opus-4-7") || model.api.id.contains("opus-4.7");
			return variantsFromEfforts(adaptiveEfforts, effort -> record1("reasoningConfig", adaptiveReasoningConfig(effort, summarized)));
		}

		if (model.api.id.contains("anthropic"))
			return thinkingBudgetVariants("reasoningConfig", 16000, 31999);

		return variantsFromEfforts(WIDELY_SUPPORTED_EFFORTS, effort -> record1("reasoningConfig", record2("type", "enabled", "maxReasoningEffort", effort)));
	}

	static function googleVariants(id:String):ProviderVariants {
		if (id.contains("2.5"))
			return googleBudgetVariants();

		final levels = id.contains("3.1") ? ["low", "medium", "high"] : ["low", "high"];
		return variantsFromEfforts(levels, effort -> record1("thinkingConfig", record2("includeThoughts", true, "thinkingLevel", effort)));
	}

	static function sapVariants(model:ProviderModel, id:String, adaptiveEfforts:Array<String>):ProviderVariants {
		if (model.api.id.contains("anthropic")) {
			if (adaptiveEfforts.length > 0)
				return variantsFromEfforts(adaptiveEfforts, effort -> record2("thinking", record1("type", "adaptive"), "effort", effort));
			return thinkingBudgetVariants("thinking");
		}
		if (model.api.id.contains("gemini") && id.contains("2.5"))
			return googleBudgetVariants();
		if (model.api.id.contains("gpt") || ~/\bo[1-9]/.match(model.api.id))
			return variantsFromEfforts(WIDELY_SUPPORTED_EFFORTS, effort -> record1("reasoningEffort", effort));
		return variantMap();
	}

	static function anthropicAdaptiveEfforts(apiID:String):Array<String> {
		if (apiID.contains("opus-4-7") || apiID.contains("opus-4.7"))
			return ["low", "medium", "high", "xhigh", "max"];
		if (apiID.contains("opus-4-6") || apiID.contains("opus-4.6") || apiID.contains("sonnet-4-6") || apiID.contains("sonnet-4.6"))
			return ["low", "medium", "high", "max"];
		return [];
	}

	static function variantsFromEfforts(efforts:Array<String>, build:String->ProviderOptions):ProviderVariants {
		final result = variantMap();
		for (effort in efforts)
			result.set(effort, build(effort));
		return result;
	}

	static function singleVariant(name:String, options:ProviderOptions):ProviderVariants {
		final result = variantMap();
		result.set(name, options);
		return result;
	}

	static function openAiEffortOptions(effort:String):ProviderOptions {
		return record3("reasoningEffort", effort, "reasoningSummary", "auto", "include", ["reasoning.encrypted_content"]);
	}

	static function adaptiveThinking(displaySummarized:Bool):ProviderOptions {
		final result = record1("type", "adaptive");
		if (displaySummarized)
			result.set("display", "summarized");
		return result;
	}

	static function adaptiveReasoningConfig(effort:String, displaySummarized:Bool):ProviderOptions {
		final result = record2("type", "adaptive", "maxReasoningEffort", effort);
		if (displaySummarized)
			result.set("display", "summarized");
		return result;
	}

	static function thinkingBudgetVariants(key:String, ?highBudget:Float = 16000, ?maxBudget:Float = 31999):ProviderVariants {
		final result = variantMap();
		result.set("high", record1(key, record2("type", "enabled", "budgetTokens", highBudget)));
		result.set("max", record1(key, record2("type", "enabled", "budgetTokens", maxBudget)));
		return result;
	}

	static function googleBudgetVariants():ProviderVariants {
		final result = variantMap();
		result.set("high", record1("thinkingConfig", record2("includeThoughts", true, "thinkingBudget", 16000)));
		result.set("max", record1("thinkingConfig", record2("includeThoughts", true, "thinkingBudget", 24576)));
		return result;
	}

	static function gatewaySlug(apiID:String):Null<String> {
		final slash = apiID.indexOf("/");
		if (slash <= 0)
			return null;
		final raw = apiID.substr(0, slash);
		return switch raw {
			case "amazon": "bedrock";
			case _: raw;
		}
	}

	static function sdkKey(npm:String):Null<String> {
		return switch npm {
			case "@ai-sdk/github-copilot": "copilot";
			case "@ai-sdk/azure": "azure";
			case "@ai-sdk/openai": "openai";
			case "@ai-sdk/amazon-bedrock": "bedrock";
			case "@ai-sdk/anthropic" | "@ai-sdk/google-vertex/anthropic": "anthropic";
			case "@ai-sdk/google-vertex": "vertex";
			case "@ai-sdk/google": "google";
			case "@ai-sdk/gateway": "gateway";
			case "@openrouter/ai-sdk-provider": "openrouter";
			case _: null;
		}
	}

	static function optionBool(options:Null<ProviderOptions>, key:String):Bool {
		if (options == null || !options.exists(key))
			return false;
		final value = options.get(key);
		return Std.isOfType(value, Bool) && value == true;
	}

	static function variantMap():ProviderVariants {
		return new haxe.DynamicAccess<ProviderOptions>();
	}

	static function optionMap():ProviderOptions {
		// ProviderOptions mirrors upstream's provider-SDK passthrough record. The
		// transform module owns these open maps only at the SDK request boundary;
		// stable provider-specific fields should graduate to typed facades.
		return new haxe.DynamicAccess<Dynamic>();
	}

	static function record1<T>(key:String, value:T):ProviderOptions {
		final result = optionMap();
		result.set(key, value);
		return result;
	}

	static function record2<A, B>(keyA:String, valueA:A, keyB:String, valueB:B):ProviderOptions {
		final result = optionMap();
		result.set(keyA, valueA);
		result.set(keyB, valueB);
		return result;
	}

	static function record3<A, B, C>(keyA:String, valueA:A, keyB:String, valueB:B, keyC:String, valueC:C):ProviderOptions {
		final result = optionMap();
		result.set(keyA, valueA);
		result.set(keyB, valueB);
		result.set(keyC, valueC);
		return result;
	}

	static function empty(options:ProviderOptions):Bool {
		for (_ in options.keys())
			return false;
		return true;
	}

	static inline function optionValue(options:ProviderOptions, key:String):Unknown {
		return Unknown.fromBoundary(options.get(key));
	}

	static function isRecord(value:Unknown):Bool {
		return UnknownNarrow.record(value) != null;
	}

	static function mergeRecord(current:Unknown, next:ProviderOptions):ProviderOptions {
		// `current` comes from the open ProviderOptions SDK boundary. It is
		// narrowed to an unknown-record view before copying and immediately
		// returned as SDK passthrough data rather than core application state.
		final result = optionMap();
		final currentRecord = UnknownNarrow.record(current);
		if (currentRecord != null) {
			for (field in currentRecord.keys())
				result.set(field, currentRecord.get(field));
		}
		for (field in next.keys())
			result.set(field, next.get(field));
		return result;
	}
}
