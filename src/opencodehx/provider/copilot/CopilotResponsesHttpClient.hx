package opencodehx.provider.copilot;

import genes.js.Async.await;
import genes.ts.Undefinable;
import haxe.DynamicAccess;
import haxe.Json;
import js.html.AbortSignal;
import js.html.Response;
import js.lib.Date;
import js.lib.Promise;
import opencodehx.externs.ai.AiSdk.AiProviderStreamPart;
import opencodehx.externs.web.WebStreams.WebHeadersAccess;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatApiError;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatFetchFunction;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatFetchInit;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarning;
import opencodehx.provider.copilot.CopilotOpenAICompatibleProvider.CopilotOpenAICompatibleModelConfig;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotMappedResponsesUsage;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesGeneratedContent;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesResponseBody;
import opencodehx.provider.copilot.CopilotResponsesRequest.CopilotResponsesArgs;
import opencodehx.provider.copilot.CopilotResponsesRequest.CopilotResponsesRequestOptions;
import opencodehx.provider.copilot.CopilotResponsesRequest.CopilotResponsesStreamArgs;

typedef CopilotResponsesHttpRequestInfo = {
	final body:String;
}

typedef CopilotResponsesGenerateResponseInfo = {
	final id:Undefinable<String>;
	final modelId:Undefinable<String>;
	final timestamp:Undefinable<Date>;
	final headers:DynamicAccess<String>;
	final body:CopilotResponsesResponseBody;
	final rawBody:String;
}

typedef CopilotResponsesGenerateResult = {
	final content:Array<CopilotResponsesGeneratedContent>;
	final finishReason:opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedFinishReason;
	final usage:CopilotMappedResponsesUsage;
	final request:CopilotResponsesHttpRequestInfo;
	final response:CopilotResponsesGenerateResponseInfo;
	final warnings:Array<CopilotChatWarning>;
}

typedef CopilotResponsesStreamResponseInfo = {
	final headers:DynamicAccess<String>;
}

typedef CopilotResponsesStreamResult = {
	final events:Array<AiProviderStreamPart>;
	final request:CopilotResponsesHttpRequestInfo;
	final response:CopilotResponsesStreamResponseInfo;
	final warnings:Array<CopilotChatWarning>;
}

typedef CopilotResponsesGenerateOptions = {
	final modelConfig:CopilotOpenAICompatibleModelConfig;
	final request:CopilotResponsesRequestOptions;
	@:optional final headers:DynamicAccess<String>;
	@:optional final fetcher:CopilotChatFetchFunction;
	@:optional final generateId:Void->String;
	@:optional final abortSignal:AbortSignal;
}

typedef CopilotResponsesStreamOptions = {
	final modelConfig:CopilotOpenAICompatibleModelConfig;
	final request:CopilotResponsesRequestOptions;
	@:optional final headers:DynamicAccess<String>;
	@:optional final fetcher:CopilotChatFetchFunction;
	@:optional final includeRawChunks:Bool;
	@:optional final abortSignal:AbortSignal;
}

class CopilotResponsesHttpClient {
	@:async
	public static function generate(options:CopilotResponsesGenerateOptions):Promise<CopilotResponsesGenerateResult> {
		final prepared = CopilotResponsesRequest.prepare(options.request);
		final body = requestBody(prepared.args);
		final response = @:await postJson(options.modelConfig, body, options.headers, options.fetcher, options.abortSignal);
		final headers = WebHeadersAccess.toDynamicAccess(response.headers);
		final rawBody = @:await response.text();
		ensureOk(response, rawBody);
		final decoded = CopilotResponsesResponseDecoder.decodeResponse(rawBody);
		if (decoded.error != null)
			throw new CopilotChatApiError(400, decoded.error.message, rawBody);
		final generateId:Void->String = options.generateId == null ? defaultGenerateId : options.generateId;
		final mapped = CopilotResponsesCompletion.content(decoded, prepared.webSearchToolName.orNull(), generateId);
		final rawReason = decoded.incomplete_details == null ? null : decoded.incomplete_details.reason;
		return {
			content: mapped.content,
			finishReason: CopilotResponsesCompletion.finishReason(rawReason, mapped.hasFunctionCall),
			usage: CopilotResponsesCompletion.usage(decoded.usage),
			request: {
				body: body
			},
			response: {
				id: decoded.id,
				modelId: decoded.model,
				timestamp: new Date(decoded.created_at * 1000),
				headers: headers,
				body: decoded,
				rawBody: rawBody,
			},
			warnings: prepared.warnings,
		};
	}

	@:async
	public static function stream(options:CopilotResponsesStreamOptions):Promise<CopilotResponsesStreamResult> {
		final includeRawChunks = options.includeRawChunks == true;
		final prepared = CopilotResponsesRequest.prepareStream(options.request);
		final body = streamRequestBody(prepared.args);
		final response = @:await postJson(options.modelConfig, body, options.headers, options.fetcher, options.abortSignal);
		final headers = WebHeadersAccess.toDynamicAccess(response.headers);
		final rawBody = @:await response.text();
		ensureOk(response, rawBody);
		return {
			events: CopilotResponsesStream.collectText(rawBody, includeRawChunks, prepared.warnings, prepared.webSearchToolName),
			request: {body: body},
			response: {headers: headers},
			warnings: prepared.warnings,
		};
	}

	static function requestBody(args:CopilotResponsesArgs):String {
		return Json.stringify(args);
	}

	static function streamRequestBody(args:CopilotResponsesStreamArgs):String {
		return Json.stringify(args);
	}

	static function postJson(modelConfig:CopilotOpenAICompatibleModelConfig, body:String, headers:Null<DynamicAccess<String>>,
			fetcher:Null<CopilotChatFetchFunction>, abortSignal:Null<AbortSignal>):Promise<Response> {
		final fetch = fetcher == null ? defaultFetch : fetcher;
		return fetch(CopilotOpenAICompatibleProvider.url(modelConfig, "/responses"), {
			method: "POST",
			headers: requestHeaders(modelConfig.headers, headers),
			body: body,
			signal: abortSignal == null ? Undefinable.absent() : abortSignal,
		});
	}

	static function requestHeaders(providerHeaders:DynamicAccess<String>, callHeaders:Null<DynamicAccess<String>>):DynamicAccess<String> {
		final out = new DynamicAccess<String>();
		out.set("content-type", "application/json");
		copyHeaders(providerHeaders, out);
		if (callHeaders != null)
			copyHeaders(callHeaders, out);
		return out;
	}

	static function copyHeaders(source:DynamicAccess<String>, target:DynamicAccess<String>):Void {
		for (key in source.keys()) {
			final value = source.get(key);
			if (value != null)
				target.set(key.toLowerCase(), value);
		}
	}

	static function ensureOk(response:Response, rawBody:String):Void {
		if (!response.ok)
			throw apiError(response, rawBody);
	}

	static function apiError(response:Response, rawBody:String):CopilotChatApiError {
		final statusText = response.statusText == null || response.statusText == "" ? 'HTTP ${response.status}' : response.statusText;
		return new CopilotChatApiError(response.status, CopilotResponsesResponseDecoder.decodeErrorMessage(rawBody, statusText), rawBody);
	}

	static function defaultGenerateId():String {
		return "generated-responses-id";
	}

	static function defaultFetch(url:String, init:CopilotChatFetchInit):Promise<Response> {
		return opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatGlobalFetch.fetch(url, init);
	}
}
