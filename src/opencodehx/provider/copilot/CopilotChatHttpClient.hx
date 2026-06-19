package opencodehx.provider.copilot;

import genes.js.Async.await;
import genes.ts.Undefinable;
import haxe.DynamicAccess;
import haxe.Json;
import js.html.AbortSignal;
import js.html.Response;
import js.lib.Date;
import js.lib.Promise;
import opencodehx.externs.web.WebStreams.WebHeadersAccess;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotChatResponseBody;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotChatResponseChoice;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotGeneratedContent;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedFinishReason;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedResponseUsage;
import opencodehx.provider.copilot.CopilotChatRequest.CopilotChatRequestOptions;
import opencodehx.provider.copilot.CopilotChatRequest.CopilotOpenAIChatArgs;
import opencodehx.provider.copilot.CopilotChatRequest.CopilotOpenAIChatStreamArgs;
import opencodehx.provider.copilot.CopilotChatResponseDecoder.CopilotInvalidChatResponseError;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamEvent;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarning;
import opencodehx.provider.copilot.CopilotOpenAICompatibleProvider.CopilotOpenAICompatibleModelConfig;

typedef CopilotChatFetchInit = {
	final method:String;
	final headers:DynamicAccess<String>;
	final body:String;
	final signal:Undefinable<AbortSignal>;
}

typedef CopilotChatFetchFunction = (url:String, init:CopilotChatFetchInit) -> Promise<Response>;

typedef CopilotChatHttpRequestInfo = {
	final body:String;
}

typedef CopilotChatGenerateResponseInfo = {
	final id:Undefinable<String>;
	final modelId:Undefinable<String>;
	final timestamp:Undefinable<Date>;
	final headers:DynamicAccess<String>;
	final body:CopilotChatResponseBody;
	final rawBody:String;
}

typedef CopilotChatGenerateResult = {
	final content:Array<CopilotGeneratedContent>;
	final finishReason:CopilotMappedFinishReason;
	final usage:CopilotMappedResponseUsage;
	final request:CopilotChatHttpRequestInfo;
	final response:CopilotChatGenerateResponseInfo;
	final warnings:Array<CopilotChatWarning>;
}

typedef CopilotChatStreamResponseInfo = {
	final headers:DynamicAccess<String>;
}

typedef CopilotChatStreamResult = {
	final events:Array<CopilotChatStreamEvent>;
	final request:CopilotChatHttpRequestInfo;
	final response:CopilotChatStreamResponseInfo;
	final warnings:Array<CopilotChatWarning>;
}

typedef CopilotChatGenerateOptions = {
	final modelConfig:CopilotOpenAICompatibleModelConfig;
	final request:CopilotChatRequestOptions;
	@:optional final headers:DynamicAccess<String>;
	@:optional final fetcher:CopilotChatFetchFunction;
	@:optional final generateId:Void->String;
	@:optional final abortSignal:AbortSignal;
}

typedef CopilotChatStreamOptions = {
	final modelConfig:CopilotOpenAICompatibleModelConfig;
	final request:CopilotChatRequestOptions;
	@:optional final headers:DynamicAccess<String>;
	@:optional final fetcher:CopilotChatFetchFunction;
	@:optional final includeUsage:Bool;
	@:optional final includeRawChunks:Bool;
	@:optional final abortSignal:AbortSignal;
}

class CopilotChatApiError {
	public final status:Int;
	public final message:String;
	public final responseBody:String;

	public function new(status:Int, message:String, responseBody:String) {
		this.status = status;
		this.message = message;
		this.responseBody = responseBody;
	}

	public function toString():String {
		return 'Copilot chat API error ${status}: ${message}';
	}
}

@:native("globalThis")
extern class CopilotChatGlobalFetch {
	static function fetch(url:String, init:CopilotChatFetchInit):Promise<Response>;
}

class CopilotChatHttpClient {
	@:async
	public static function generate(options:CopilotChatGenerateOptions):Promise<CopilotChatGenerateResult> {
		final prepared = CopilotChatRequest.prepare(options.request);
		final body = requestBody(prepared.args);
		final response = @:await postJson(options.modelConfig, body, options.headers, options.fetcher, options.abortSignal);
		final headers = WebHeadersAccess.toDynamicAccess(response.headers);
		final rawBody = @:await response.text();
		ensureOk(response, rawBody);
		final decoded = CopilotChatResponseDecoder.decodeResponse(rawBody);
		final choice = firstChoice(decoded);
		final metadata = CopilotChatCompletion.responseMetadata(decoded);
		final generateId:Void->String = options.generateId == null ? defaultGenerateId : options.generateId;
		return {
			content: CopilotChatCompletion.responseContent(decoded, generateId),
			finishReason: CopilotChatCompletion.finishReason(choice.finish_reason),
			usage: CopilotChatCompletion.responseUsage(decoded.usage),
			request: {
				body: body
			},
			response: {
				id: metadata.id,
				modelId: metadata.modelId,
				timestamp: metadata.timestamp,
				headers: headers,
				body: decoded,
				rawBody: rawBody,
			},
			warnings: prepared.warnings,
		};
	}

	@:async
	public static function stream(options:CopilotChatStreamOptions):Promise<CopilotChatStreamResult> {
		final includeUsage = options.includeUsage == true;
		final includeRawChunks = options.includeRawChunks == true;
		final prepared = CopilotChatRequest.prepareStream(options.request, includeUsage);
		final body = streamRequestBody(prepared.args);
		final response = @:await postJson(options.modelConfig, body, options.headers, options.fetcher, options.abortSignal);
		final headers = WebHeadersAccess.toDynamicAccess(response.headers);
		if (!response.ok) {
			final rawBody = @:await response.text();
			throw apiError(response, rawBody);
		}
		final events = @:await CopilotChatStreamAdapter.responseEvents(response, includeRawChunks, prepared.warnings);
		return {
			events: events,
			request: {body: body},
			response: {headers: headers},
			warnings: prepared.warnings,
		};
	}

	static function requestBody(args:CopilotOpenAIChatArgs):String {
		return Json.stringify(args);
	}

	static function streamRequestBody(args:CopilotOpenAIChatStreamArgs):String {
		return Json.stringify(args);
	}

	static function postJson(modelConfig:CopilotOpenAICompatibleModelConfig, body:String, headers:Null<DynamicAccess<String>>,
			fetcher:Null<CopilotChatFetchFunction>, abortSignal:Null<AbortSignal>):Promise<Response> {
		final fetch = fetcher == null ? defaultFetch : fetcher;
		return fetch(CopilotOpenAICompatibleProvider.url(modelConfig, "/chat/completions"), {
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
		return new CopilotChatApiError(response.status, CopilotChatResponseDecoder.decodeErrorMessage(rawBody, statusText), rawBody);
	}

	static function firstChoice(response:CopilotChatResponseBody):CopilotChatResponseChoice {
		if (response.choices.length == 0)
			throw new CopilotInvalidChatResponseError("Expected at least one chat response choice.");
		return response.choices[0];
	}

	static function defaultGenerateId():String {
		return "generated-tool-call";
	}

	static function defaultFetch(url:String, init:CopilotChatFetchInit):Promise<Response> {
		return CopilotChatGlobalFetch.fetch(url, init);
	}
}
