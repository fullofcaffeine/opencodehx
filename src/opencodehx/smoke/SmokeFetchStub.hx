package opencodehx.smoke;

import haxe.DynamicAccess;
import haxe.Json;
import js.html.Headers;
import js.html.Request;
import js.html.Response;
import js.html.URL;
import js.Syntax;
import js.lib.Promise;
import js.lib.Uint8Array;
import opencodehx.externs.web.Fetch.FetchInput;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.externs.web.WebStreams.WebReadableStreamDefaultController;
import opencodehx.externs.web.WebStreams.WebTextEncoder;

typedef SmokeFetchStubInit = {
	@:optional final headers:DynamicAccess<String>;
	@:optional final method:String;
	@:optional final body:String;
}

typedef SmokeFetchStubCallback = (url:FetchInput, ?init:SmokeFetchStubInit) -> Promise<Response>;

/**
	Opaque handle for the host's real `typeof fetch` declaration.

	Haxe's `js.html.RequestInit` typedef is close to, but not identical to,
	TypeScript's DOM `RequestInit` under strict checking. The smoke fixture only
	needs to store and replace the host fetch function, so this named opaque type
	keeps that exact TypeScript surface without spreading raw `Syntax.code`.
**/
@:ts.type("typeof fetch")
abstract SmokeFetchStubFunction(SmokeFetchStubCallback) {
	@:noCompletion
	public static function fromStub(callback:SmokeFetchStubCallback):SmokeFetchStubFunction {
		// The stub callback handles the subset used by these smoke tests:
		// string/URL/Request input and optional headers. Cast only at the
		// monkey-patch boundary so the body stays typed Haxe.
		return Syntax.code("{0} as typeof fetch", callback);
	}
}

@:native("globalThis")
extern class SmokeFetchGlobal {
	static var fetch:SmokeFetchStubFunction;
}

/**
	Opaque handle for the original `globalThis.fetch` implementation.

	The handle is intentionally opaque because smoke tests only need to restore
	the host fetch function after a monkey-patched scenario; callers should never
	inspect or invoke the captured global directly.
**/
abstract SmokeFetchHandle(SmokeFetchStubFunction) {
	@:noCompletion
	public inline function new(value:SmokeFetchStubFunction) {
		this = value;
	}

	@:noCompletion
	public inline function raw():SmokeFetchStubFunction {
		return this;
	}
}

/**
	Smoke-only fetch monkey patch for remote config fixtures.

	The tests need to replace `globalThis.fetch` inside the current Node process
	so CLI/config paths can exercise remote loading without external network
	calls. Keep the mutation and ad-hoc observation fields behind this typed
	smoke facade so product code never depends on process-global test state.
**/
class SmokeFetchStub {
	static var configFetchedUrlValue:Null<String>;
	static var cliFetchedUrlValue:Null<String>;
	static var cliAccountAuthValue:Null<String>;
	static var cliAccountOrgValue:Null<String>;
	static var liveFetchedUrlValue:Null<String>;
	static var liveAuthValue:Null<String>;
	static var liveRequestBodyValue:Null<String>;

	public static function installConfigRemote():SmokeFetchHandle {
		final originalFetch = new SmokeFetchHandle(SmokeFetchGlobal.fetch);
		configFetchedUrlValue = null;
		SmokeFetchGlobal.fetch = SmokeFetchStubFunction.fromStub(configRemoteFetch);
		return originalFetch;
	}

	public static function installCliRemote():SmokeFetchHandle {
		final originalFetch = new SmokeFetchHandle(SmokeFetchGlobal.fetch);
		cliFetchedUrlValue = null;
		cliAccountAuthValue = null;
		cliAccountOrgValue = null;
		SmokeFetchGlobal.fetch = SmokeFetchStubFunction.fromStub(cliRemoteFetch);
		return originalFetch;
	}

	public static function installCliLiveSuccess():SmokeFetchHandle {
		final originalFetch = new SmokeFetchHandle(SmokeFetchGlobal.fetch);
		liveFetchedUrlValue = null;
		liveAuthValue = null;
		liveRequestBodyValue = null;
		SmokeFetchGlobal.fetch = SmokeFetchStubFunction.fromStub(cliLiveFetch);
		return originalFetch;
	}

	public static function installCliLiveFailure():SmokeFetchHandle {
		final originalFetch = new SmokeFetchHandle(SmokeFetchGlobal.fetch);
		liveFetchedUrlValue = null;
		liveAuthValue = null;
		liveRequestBodyValue = null;
		SmokeFetchGlobal.fetch = SmokeFetchStubFunction.fromStub(cliLiveFailureFetch);
		return originalFetch;
	}

	public static function restore(originalFetch:SmokeFetchHandle):Void {
		SmokeFetchGlobal.fetch = originalFetch.raw();
	}

	public static function configFetchedUrl():Null<String> {
		return configFetchedUrlValue;
	}

	public static function cliFetchedUrl():Null<String> {
		return cliFetchedUrlValue;
	}

	public static function cliAccountAuth():Null<String> {
		return cliAccountAuthValue;
	}

	public static function cliAccountOrg():Null<String> {
		return cliAccountOrgValue;
	}

	public static function liveFetchedUrl():Null<String> {
		return liveFetchedUrlValue;
	}

	public static function liveAuth():Null<String> {
		return liveAuthValue;
	}

	public static function liveRequestBody():Null<String> {
		return liveRequestBodyValue;
	}

	static function configRemoteFetch(url:FetchInput, ?init:SmokeFetchStubInit):Promise<Response> {
		configFetchedUrlValue = inputText(url);
		return response({
			config: {
				username: "{env:TEST_TOKEN}",
				mcp: {jira: {type: "remote", url: "https://jira.example.com/mcp", enabled: false}}
			}
		});
	}

	static function cliRemoteFetch(url:FetchInput, ?init:SmokeFetchStubInit):Promise<Response> {
		final text = inputText(url);
		cliFetchedUrlValue = text;
		if (StringTools.endsWith(text, "/api/config")) {
			final headers = init == null || init.headers == null ? new Headers() : new Headers(init.headers);
			cliAccountAuthValue = headers.get("authorization");
			cliAccountOrgValue = headers.get("x-org-id");
			return response({
				config: {
					provider: {
						"account-live": {
							npm: "@ai-sdk/openai-compatible",
							name: "Account Live",
							options: {baseURL: "https://account.example.com/v1", apiKey: "{env:OPENCODE_CONSOLE_TOKEN}"},
							models: {chat: {name: "Chat"}}
						}
					}
				}
			});
		}
		return response({
			config: {
				provider: {
					"remote-live": {
						npm: "@ai-sdk/openai-compatible",
						name: "Remote Live",
						options: {baseURL: "https://remote.example.com/v1", apiKey: "{env:LIVE_REMOTE_TOKEN}"},
						models: {chat: {name: "Chat"}}
					}
				}
			}
		});
	}

	static function cliLiveFetch(url:FetchInput, ?init:SmokeFetchStubInit):Promise<Response> {
		final text = inputText(url);
		liveFetchedUrlValue = text;
		final headers = init == null || init.headers == null ? new Headers() : new Headers(init.headers);
		liveAuthValue = headers.get("authorization");
		liveRequestBodyValue = init == null ? null : init.body;
		if (StringTools.endsWith(text, "/remote-instructions.md"))
			return Promise.resolve(new Response("# Remote Instructions\nUse remote instruction rules.", {status: 200}));
		if (StringTools.endsWith(text, "/chat/completions"))
			return Promise.resolve(streamResponse([
				"data: " + Json.stringify({
					id: "chatcmpl-local-live",
					created: 1,
					model: "chat",
					choices: [{delta: {role: "assistant", content: "Hello "}}],
				}) + "\n\n",
				"data: " + Json.stringify({
					id: "chatcmpl-local-live",
					created: 1,
					model: "chat",
					choices: [{delta: {content: "from local live."}}],
				}) + "\n\n",
				"data: " + Json.stringify({
					id: "chatcmpl-local-live",
					created: 1,
					model: "chat",
					choices: [{delta: {}, finish_reason: "stop"}],
					usage: {prompt_tokens: 7, completion_tokens: 4, total_tokens: 11},
				}) + "\n\n",
				"data: [DONE]\n\n"
			]));
		return Promise.resolve(new Response("not found", {status: 404}));
	}

	static function cliLiveFailureFetch(url:FetchInput, ?init:SmokeFetchStubInit):Promise<Response> {
		final text = inputText(url);
		liveFetchedUrlValue = text;
		final headers = init == null || init.headers == null ? new Headers() : new Headers(init.headers);
		liveAuthValue = headers.get("authorization");
		liveRequestBodyValue = init == null ? null : init.body;
		if (StringTools.endsWith(text, "/chat/completions"))
			return Promise.resolve(new Response(Json.stringify({error: {message: "local live failure"}}), {
				status: 500,
				headers: headerMap("content-type", "application/json"),
			}));
		return Promise.resolve(new Response("not found", {status: 404}));
	}

	static function inputText(input:FetchInput):String {
		if (Std.isOfType(input, Request)) {
			// FetchInput is an EitherType; after the runtime Request proof, the
			// cast exposes the branch-specific url field.
			return (cast input : Request).url;
		}
		if (Std.isOfType(input, URL)) {
			// FetchInput is an EitherType; after the runtime URL proof, the cast
			// exposes the branch-specific href field.
			return (cast input : URL).href;
		}
		return Std.string(input);
	}

	static function response(body:Dynamic):Promise<Response> {
		// Smoke response payloads deliberately mirror loose remote config JSON.
		// The Dynamic value is immediately serialized and never escapes this
		// test-only fetch stub as an application value.
		return Promise.resolve(new Response(Json.stringify(body), {status: 200}));
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

	static function headerMap(name:String, value:String):DynamicAccess<String> {
		final headers = new DynamicAccess<String>();
		headers.set(name, value);
		return headers;
	}
}
