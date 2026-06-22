package opencodehx.smoke;

import genes.js.Async.await;
import haxe.DynamicAccess;
import js.html.Response;
import js.lib.Promise;
import js.lib.Uint8Array;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.externs.web.WebStreams.WebReadableStreamDefaultController;
import opencodehx.externs.web.WebStreams.WebTextEncoder;
import opencodehx.provider.copilot.CopilotChatHttpClient;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatApiError;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatFetchFunction;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatFetchInit;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptMessage;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptPart;
import opencodehx.provider.copilot.CopilotChatRequest;
import opencodehx.provider.copilot.CopilotChatResponseDecoder.CopilotInvalidChatResponseError;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamEventType;
import opencodehx.provider.copilot.CopilotOpenAICompatibleProvider;

typedef CopilotCapturedFetchRequest = {
	final url:String;
	final init:CopilotChatFetchInit;
}

class CopilotChatHttpClientSmoke {
	@:async
	public static function run():Promise<Void> {
		final calls:Array<CopilotCapturedFetchRequest> = [];
		final responses = [
			jsonResponse(generateResponseJson(), 200, "OK", headerMap("x-request-id", "generate-req")),
			streamResponse([
				'data: {"id":"chatcmpl-stream","created":1677652288,"model":"gemini-2.0-flash-001","choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}\n\n',
				'data: {"choices":[{"delta":{"content":" there"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}\n\n',
				"data: [DONE]\n\n",
			]),
			jsonResponse('{"error":{"message":"bad token","type":"invalid_request_error"}}', 401, "Unauthorized", headerMap("x-request-id", "error-req")),
			jsonResponse('{"choices":{}}', 200, "OK", headerMap("x-request-id", "invalid-req")),
		];
		final fetcher = fakeFetcher(calls, responses);

		final generateOptions = requestOptions();
		generateOptions.topK = 4;
		final callHeaders = headerMap("x-custom", "override");
		final generated = @:await CopilotChatHttpClient.generate({
			modelConfig: modelConfig(),
			request: generateOptions,
			headers: callHeaders,
			fetcher: fetcher,
		});
		eq(calls[0].url, "https://api.githubcopilot.com/chat/completions", "generate url");
		eq(calls[0].init.method, "POST", "generate method");
		eq(calls[0].init.headers.get("authorization"), "Bearer github-token", "authorization header");
		eq(calls[0].init.headers.get("x-custom"), "override", "call header override");
		eq(calls[0].init.headers.get("content-type"), "application/json", "content-type header");
		contains(calls[0].init.body, '"model":"gemini-2.0-flash-001"', "generate model body");
		contains(calls[0].init.body, '"messages":[{"role":"user","content":"Hello"}]', "generate messages body");
		eq(generated.content[0].text.orNull(), "Hello from API", "generated text");
		eq(generated.finishReason.raw.orNull(), "stop", "generated finish reason");
		eq(generated.usage.inputTokens.total.orNull(), 5.0, "generated prompt tokens");
		eq(generated.response.headers.get("x-request-id"), "generate-req", "generate response header");
		eq(generated.warnings[0].feature, "topK", "generate warning");

		final streamOptions = requestOptions();
		streamOptions.topK = 8;
		final streamed = @:await CopilotChatHttpClient.stream({
			modelConfig: modelConfig(),
			request: streamOptions,
			includeUsage: true,
			includeRawChunks: true,
			fetcher: fetcher,
		});
		contains(calls[1].init.body, '"stream":true', "stream flag body");
		contains(calls[1].init.body, '"stream_options":{"include_usage":true}', "stream usage body");
		eq(streamed.events[0].type, CopilotChatStreamEventType.StreamStart, "stream start");
		eq(present(streamed.events[0].warnings.orNull(), "stream warnings")[0].feature, "topK", "stream warning");
		eq(streamed.events[1].type, CopilotChatStreamEventType.Raw, "stream raw");
		eq(streamed.events[4].delta.orNull(), "Hi", "stream first text");
		eq(streamed.events[6].delta.orNull(), " there", "stream second text");

		try {
			@:await CopilotChatHttpClient.generate({
				modelConfig: modelConfig(),
				request: requestOptions(),
				fetcher: fetcher,
			});
			throw "expected Copilot API error";
		} catch (error:CopilotChatApiError) {
			eq(error.status, 401, "error status");
			eq(error.message, "bad token", "error message");
		}

		try {
			@:await CopilotChatHttpClient.generate({
				modelConfig: modelConfig(),
				request: requestOptions(),
				fetcher: fetcher,
			});
			throw "expected invalid Copilot response";
		} catch (error:CopilotInvalidChatResponseError) {
			eq(error.message, "Expected 'choices' to be an array.", "invalid response message");
		}

		return null;
	}

	static function requestOptions() {
		return CopilotChatRequest.options("gemini-2.0-flash-001", [CopilotPromptMessage.User([CopilotPromptPart.Text("Hello")])]);
	}

	static function modelConfig() {
		final headers = headerMap("x-provider", "base");
		return CopilotOpenAICompatibleProvider.chat(CopilotOpenAICompatibleProvider.settings("github-token", "https://api.githubcopilot.com",
			"github-copilot", headers), "gemini-2.0-flash-001");
	}

	static function fakeFetcher(calls:Array<CopilotCapturedFetchRequest>, responses:Array<Response>):CopilotChatFetchFunction {
		return function(url:String, init:CopilotChatFetchInit):Promise<Response> {
			calls.push({url: url, init: init});
			final response = responses.shift();
			if (response == null)
				throw "missing fake Copilot response";
			final present:Response = response;
			return Promise.resolve(present);
		}
	}

	static function jsonResponse(body:String, status:Int, statusText:String, headers:DynamicAccess<String>):Response {
		return new Response(body, {
			status: status,
			statusText: statusText,
			headers: headers,
		});
	}

	static function streamResponse(chunks:Array<String>):Response {
		final stream = new WebReadableStream<Uint8Array>({
			start: controller -> enqueueChunks(controller, chunks),
		});
		return new Response(stream, {
			status: 200,
			headers: headerMap("content-type", "text/event-stream"),
		});
	}

	static function enqueueChunks(controller:WebReadableStreamDefaultController<Uint8Array>, chunks:Array<String>):Void {
		final encoder = new WebTextEncoder();
		for (chunk in chunks)
			controller.enqueue(encoder.encode(chunk));
		controller.close();
	}

	static function generateResponseJson():String {
		return
			'{"id":"chatcmpl-generate","created":1677652288,"model":"gemini-2.0-flash-001","choices":[{"message":{"role":"assistant","content":"Hello from API","reasoning_opaque":"opaque-token"},"finish_reason":"stop"}],"usage":{"prompt_tokens":5,"completion_tokens":7,"total_tokens":12,"prompt_tokens_details":{"cached_tokens":2},"completion_tokens_details":{"reasoning_tokens":3}}}';
	}

	static function headerMap(name:String, value:String):DynamicAccess<String> {
		final headers = new DynamicAccess<String>();
		headers.set(name, value);
		return headers;
	}

	static function present<T>(value:Null<T>, label:String):T {
		if (value == null)
			throw '${label}: expected value';
		return value;
	}

	static function contains(value:String, expected:String, label:String):Void {
		if (value.indexOf(expected) < 0)
			throw '$label: expected ${value} to contain ${expected}';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
