package opencodehx.smoke;

import haxe.DynamicAccess;
import haxe.Json;
import js.html.Headers;
import js.html.Request;
import js.html.Response;
import js.html.URL;
import js.Syntax;
import js.lib.Promise;
import opencodehx.externs.web.Fetch.FetchInput;

typedef SmokeFetchStubInit = {
	@:optional final headers:DynamicAccess<String>;
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
}
