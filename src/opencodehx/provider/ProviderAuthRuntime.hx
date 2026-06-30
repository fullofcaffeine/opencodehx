package opencodehx.provider;

import opencodehx.auth.AuthStore.AuthEntry;
import opencodehx.plugin.PluginAuthHooks;
import opencodehx.plugin.PluginAuthHooks.PluginAuthAuthorization;
import opencodehx.plugin.PluginAuthHooks.PluginAuthAuthorizationMethod;
import opencodehx.plugin.PluginAuthHooks.PluginAuthCallbackResult;
import opencodehx.plugin.PluginAuthHooks.PluginAuthHook;
import opencodehx.plugin.PluginAuthHooks.PluginAuthInput;
import opencodehx.plugin.PluginAuthHooks.PluginAuthMethodType;
import opencodehx.provider.ProviderTypes.ProviderID;

typedef ProviderAuthRuntimeAuthorization = {
	final url:String;
	final method:PluginAuthAuthorizationMethod;
	final instructions:String;
}

typedef ProviderAuthWriter = (ProviderID, AuthEntry) -> Void;

enum ProviderAuthRuntimeResult<T> {
	Accepted(value:T);
	NoContent;
	Rejected(message:String, status:Int);
}

/**
	Small provider-auth service used by the server route minimum.

	Upstream builds this from live plugin hooks plus Effect InstanceState. This
	runtime keeps the same semantics that matter for the first route evidence:
	auth methods are keyed by provider, OAuth authorize stores a pending callback
	per provider, and callback success persists through AuthStore. Live plugin
	loading and browser/device OAuth flows stay outside this injected seam.
**/
class ProviderAuthRuntime {
	final hooks:Array<PluginAuthHook>;
	final writeAuth:ProviderAuthWriter;
	final pending = new Map<String, PluginAuthAuthorization>();

	public function new(hooks:Array<PluginAuthHook>, writeAuth:ProviderAuthWriter) {
		this.hooks = PluginAuthHooks.concat([], hooks);
		this.writeAuth = writeAuth;
	}

	public function methods():Array<PluginAuthHook> {
		return PluginAuthHooks.concat([], hooks);
	}

	public function authorize(providerID:ProviderID, methodIndex:Int,
			inputs:Null<Array<PluginAuthInput>>):ProviderAuthRuntimeResult<ProviderAuthRuntimeAuthorization> {
		final method = methodAt(providerID, methodIndex);
		if (method == null)
			return Rejected("Provider auth method not found", 400);
		if (method.type != PluginAuthMethodType.OAuth)
			return NoContent;
		final authorize = method.authorize.orNull();
		if (authorize == null)
			return Rejected("Provider OAuth authorize is not configured", 400);
		final authorization = authorize(inputs);
		pending.set(providerID.toString(), authorization);
		return Accepted({
			url: authorization.url,
			method: authorization.method,
			instructions: authorization.instructions,
		});
	}

	public function callback(providerID:ProviderID, _methodIndex:Int, code:Null<String>):ProviderAuthRuntimeResult<Bool> {
		final authorization = pending.get(providerID.toString());
		if (authorization == null)
			return Rejected("ProviderAuthOauthMissing", 400);
		if (authorization.method == PluginAuthAuthorizationMethod.Code && code == null)
			return Rejected("ProviderAuthOauthCodeMissing", 400);
		final result = authorization.callback(code);
		return switch result {
			case Api(value):
				writeAuth(providerID, {
					type: "api",
					key: value.key,
				});
				pending.remove(providerID.toString());
				Accepted(true);
			case OAuth(value):
				writeAuth(providerID, {
					type: "oauth",
					access: value.access,
					refresh: value.refresh,
					expires: value.expires,
					accountId: value.accountId.orNull(),
					enterpriseUrl: value.enterpriseUrl.orNull(),
				});
				pending.remove(providerID.toString());
				Accepted(true);
			case Failed:
				Rejected("ProviderAuthOauthCallbackFailed", 400);
		}
	}

	function methodAt(providerID:ProviderID, methodIndex:Int):Null<opencodehx.plugin.PluginAuthHooks.PluginAuthMethod> {
		final methods = PluginAuthHooks.methodsFor(providerID, hooks);
		return methodIndex < 0 || methodIndex >= methods.length ? null : methods[methodIndex];
	}
}
