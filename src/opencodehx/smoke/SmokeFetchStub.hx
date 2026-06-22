package opencodehx.smoke;

import js.Syntax;

/**
	Opaque handle for the original `globalThis.fetch` implementation.

	The backing value is Dynamic because it is captured from a mutable JavaScript
	global, but callers cannot inspect or call it; they can only pass it back to
	`SmokeFetchStub.restore`.
**/
abstract SmokeFetchHandle(Dynamic) {
	@:noCompletion
	public static inline function capture(value:Dynamic):SmokeFetchHandle {
		return cast value;
	}

	@:noCompletion
	public inline function raw():Dynamic {
		return this;
	}
}

/**
	Smoke-only fetch monkey patch for remote config fixtures.

	The tests need to replace `globalThis.fetch` inside the current Node process
	so CLI/config paths can exercise remote loading without external network
	calls. Haxe cannot type global property mutation or the ad-hoc observation
	fields we attach to `globalThis`, so the raw JavaScript is quarantined here
	instead of being repeated through smoke scenarios.
**/
class SmokeFetchStub {
	public static function installConfigRemote():SmokeFetchHandle {
		final originalFetch = SmokeFetchHandle.capture(Syntax.code("globalThis.fetch"));
		Syntax.code("(globalThis as unknown as { __opencodehxFetchedUrl?: string }).__opencodehxFetchedUrl = undefined");
		Syntax.code("globalThis.fetch = (url: string | URL | Request) => {
			const text = url instanceof Request ? url.url : url instanceof URL ? url.href : String(url);
			(globalThis as unknown as { __opencodehxFetchedUrl?: string }).__opencodehxFetchedUrl = text;
			return Promise.resolve(new Response(JSON.stringify({
				config: {
					username: '{env:TEST_TOKEN}',
					mcp: { jira: { type: 'remote', url: 'https://jira.example.com/mcp', enabled: false } }
				}
			}), { status: 200 }));
		}");
		return originalFetch;
	}

	public static function installCliRemote():SmokeFetchHandle {
		final originalFetch = SmokeFetchHandle.capture(Syntax.code("globalThis.fetch"));
		Syntax.code("(globalThis as unknown as {
			__opencodehxCliFetchedUrl?: string;
			__opencodehxCliAccountAuth?: string;
			__opencodehxCliAccountOrg?: string;
		}).__opencodehxCliFetchedUrl = undefined");
		Syntax.code("(globalThis as unknown as {
			__opencodehxCliFetchedUrl?: string;
			__opencodehxCliAccountAuth?: string;
			__opencodehxCliAccountOrg?: string;
		}).__opencodehxCliAccountAuth = undefined");
		Syntax.code("(globalThis as unknown as {
			__opencodehxCliFetchedUrl?: string;
			__opencodehxCliAccountAuth?: string;
			__opencodehxCliAccountOrg?: string;
		}).__opencodehxCliAccountOrg = undefined");
		Syntax.code("globalThis.fetch = (url: string | URL | Request, init?: { headers?: HeadersInit }) => {
			const text = url instanceof Request ? url.url : url instanceof URL ? url.href : String(url);
			(globalThis as unknown as { __opencodehxCliFetchedUrl?: string }).__opencodehxCliFetchedUrl = text;
			if (text.endsWith('/api/config')) {
				const headers = new Headers(init?.headers);
				(globalThis as unknown as { __opencodehxCliAccountAuth?: string }).__opencodehxCliAccountAuth =
					headers.get('authorization') ?? undefined;
				(globalThis as unknown as { __opencodehxCliAccountOrg?: string }).__opencodehxCliAccountOrg =
					headers.get('x-org-id') ?? undefined;
				return Promise.resolve(new Response(JSON.stringify({
					config: {
						provider: {
							'account-live': {
								npm: '@ai-sdk/openai-compatible',
								name: 'Account Live',
								options: { baseURL: 'https://account.example.com/v1', apiKey: '{env:OPENCODE_CONSOLE_TOKEN}' },
								models: { chat: { name: 'Chat' } }
							}
						}
					}
				}), { status: 200 }));
			}
			return Promise.resolve(new Response(JSON.stringify({
				config: {
					provider: {
						'remote-live': {
							npm: '@ai-sdk/openai-compatible',
							name: 'Remote Live',
							options: { baseURL: 'https://remote.example.com/v1', apiKey: '{env:LIVE_REMOTE_TOKEN}' },
							models: { chat: { name: 'Chat' } }
						}
					}
				}
			}), { status: 200 }));
		}");
		return originalFetch;
	}

	public static function restore(originalFetch:SmokeFetchHandle):Void {
		Syntax.code("globalThis.fetch = {0}", originalFetch.raw());
	}

	public static function configFetchedUrl():Null<String> {
		return Syntax.code("(globalThis as unknown as { __opencodehxFetchedUrl?: string }).__opencodehxFetchedUrl ?? null");
	}

	public static function cliFetchedUrl():Null<String> {
		return Syntax.code("(globalThis as unknown as { __opencodehxCliFetchedUrl?: string }).__opencodehxCliFetchedUrl ?? null");
	}

	public static function cliAccountAuth():Null<String> {
		return Syntax.code("(globalThis as unknown as { __opencodehxCliAccountAuth?: string }).__opencodehxCliAccountAuth ?? null");
	}

	public static function cliAccountOrg():Null<String> {
		return Syntax.code("(globalThis as unknown as { __opencodehxCliAccountOrg?: string }).__opencodehxCliAccountOrg ?? null");
	}
}
