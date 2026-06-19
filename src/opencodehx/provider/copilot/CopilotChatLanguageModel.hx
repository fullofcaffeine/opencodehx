package opencodehx.provider.copilot;

import haxe.DynamicAccess;
import js.html.AbortSignal;
import js.lib.Promise;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatFetchFunction;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatGenerateResult;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatStreamResult;
import opencodehx.provider.copilot.CopilotChatRequest.CopilotChatRequestOptions;
import opencodehx.provider.copilot.CopilotOpenAICompatibleProvider.CopilotOpenAICompatibleModelConfig;

using StringTools;

typedef CopilotChatLanguageModelConfig = {
	final modelConfig:CopilotOpenAICompatibleModelConfig;
	@:optional final fetcher:CopilotChatFetchFunction;
	@:optional final includeUsage:Bool;
	@:optional final supportsStructuredOutputs:Bool;
	@:optional final supportedUrls:DynamicAccess<Array<String>>;
	@:optional final generateId:Void->String;
}

/**
 * Haxe-owned equivalent of upstream's OpenAICompatibleChatLanguageModel surface.
 *
 * The lower helpers own message conversion, request shaping, HTTP transport,
 * SSE decoding, and stream-state normalization. This class owns the
 * upstream-like model identity and class-level options (`this.modelId`,
 * structured-output support, include-usage mode, and supported URL metadata).
 * Keeping those responsibilities here lets tests verify provider-class parity
 * without making every pure helper target-shaped.
 */
class CopilotChatLanguageModel {
	public final specificationVersion = "v3";
	public final modelId:String;
	public final provider:String;
	public final supportsStructuredOutputs:Bool;
	public var supportedUrls(get, never):DynamicAccess<Array<String>>;
	public var providerOptionsName(get, never):String;

	final modelConfig:CopilotOpenAICompatibleModelConfig;
	final fetcher:Null<CopilotChatFetchFunction>;
	final includeUsage:Bool;
	final supportedUrlData:DynamicAccess<Array<String>>;
	final generateId:Null<Void->String>;

	public function new(config:CopilotChatLanguageModelConfig) {
		modelConfig = config.modelConfig;
		modelId = modelConfig.modelId;
		provider = modelConfig.provider;
		fetcher = config.fetcher;
		includeUsage = config.includeUsage == true;
		supportsStructuredOutputs = config.supportsStructuredOutputs == true;
		supportedUrlData = cloneSupportedUrls(config.supportedUrls);
		generateId = config.generateId;
	}

	public function doGenerate(request:CopilotChatRequestOptions, ?headers:DynamicAccess<String>, ?abortSignal:AbortSignal):Promise<CopilotChatGenerateResult> {
		return CopilotChatHttpClient.generate({
			modelConfig: modelConfig,
			request: requestForModel(request),
			headers: headers,
			fetcher: fetcher,
			generateId: generateId,
			abortSignal: abortSignal,
		});
	}

	public function doStream(request:CopilotChatRequestOptions, ?headers:DynamicAccess<String>, ?includeRawChunks:Bool,
			?abortSignal:AbortSignal):Promise<CopilotChatStreamResult> {
		return CopilotChatHttpClient.stream({
			modelConfig: modelConfig,
			request: requestForModel(request),
			headers: headers,
			fetcher: fetcher,
			includeUsage: includeUsage,
			includeRawChunks: includeRawChunks == true,
			abortSignal: abortSignal,
		});
	}

	function requestForModel(source:CopilotChatRequestOptions):CopilotChatRequestOptions {
		final out = CopilotChatRequest.options(modelId, source.prompt);
		out.maxOutputTokens = source.maxOutputTokens;
		out.temperature = source.temperature;
		out.topP = source.topP;
		out.topK = source.topK;
		out.frequencyPenalty = source.frequencyPenalty;
		out.presencePenalty = source.presencePenalty;
		out.stopSequences = source.stopSequences;
		out.seed = source.seed;
		out.responseFormat = source.responseFormat;
		out.supportsStructuredOutputs = supportsStructuredOutputs;
		out.providerOptions = source.providerOptions;
		out.tools = source.tools;
		out.toolChoice = source.toolChoice;
		return out;
	}

	function get_supportedUrls():DynamicAccess<Array<String>> {
		return cloneSupportedUrls(supportedUrlData);
	}

	function get_providerOptionsName():String {
		final parts = provider.split(".");
		return parts.length == 0 ? "" : parts[0].trim();
	}

	static function cloneSupportedUrls(source:Null<DynamicAccess<Array<String>>>):DynamicAccess<Array<String>> {
		final out = new DynamicAccess<Array<String>>();
		if (source == null)
			return out;
		for (key in source.keys()) {
			final value = source.get(key);
			if (value != null)
				out.set(key, value.copy());
		}
		return out;
	}
}
