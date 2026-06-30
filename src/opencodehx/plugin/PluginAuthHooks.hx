package opencodehx.plugin;

import genes.ts.Undefinable;
import opencodehx.provider.ProviderTypes.ProviderID;

enum abstract PluginAuthMethodType(String) to String {
	final OAuth = "oauth";
	final Api = "api";
}

enum abstract PluginAuthAuthorizationMethod(String) to String {
	final Auto = "auto";
	final Code = "code";
}

enum abstract PluginAuthPromptWhenOp(String) to String {
	final Eq = "eq";
	final NotEq = "neq";
}

typedef PluginAuthInput = {
	final key:String;
	final value:String;
}

typedef PluginAuthPromptWhen = {
	final key:String;
	final op:PluginAuthPromptWhenOp;
	final value:String;
}

typedef PluginAuthTextPrompt = {
	final key:String;
	final message:String;
	@:optional final placeholder:Undefinable<String>;
	@:optional final when:Undefinable<PluginAuthPromptWhen>;
}

typedef PluginAuthSelectOption = {
	final label:String;
	final value:String;
	@:optional final hint:Undefinable<String>;
}

typedef PluginAuthSelectPrompt = {
	final key:String;
	final message:String;
	final options:Array<PluginAuthSelectOption>;
	@:optional final when:Undefinable<PluginAuthPromptWhen>;
}

enum PluginAuthPrompt {
	Text(prompt:PluginAuthTextPrompt);
	Select(prompt:PluginAuthSelectPrompt);
}

typedef PluginAuthApiResult = {
	final key:String;
}

typedef PluginAuthOAuthResult = {
	final access:String;
	final refresh:String;
	final expires:Float;
	@:optional final accountId:Undefinable<String>;
	@:optional final enterpriseUrl:Undefinable<String>;
}

enum PluginAuthCallbackResult {
	Api(result:PluginAuthApiResult);
	OAuth(result:PluginAuthOAuthResult);
	Failed;
}

typedef PluginAuthCallback = Null<String>->PluginAuthCallbackResult;

typedef PluginAuthAuthorization = {
	final url:String;
	final method:PluginAuthAuthorizationMethod;
	final instructions:String;
	final callback:PluginAuthCallback;
}

typedef PluginAuthAuthorize = Null<Array<PluginAuthInput>>->PluginAuthAuthorization;

typedef PluginAuthMethod = {
	final type:PluginAuthMethodType;
	final label:String;
	@:optional final prompts:Undefinable<Array<PluginAuthPrompt>>;
	@:optional final authorize:Undefinable<PluginAuthAuthorize>;
}

typedef PluginAuthHook = {
	final provider:ProviderID;
	final methods:Array<PluginAuthMethod>;
}

class PluginAuthHooks {
	public static function methodsFor(provider:ProviderID, hooks:Array<PluginAuthHook>):Array<PluginAuthMethod> {
		var matched:Null<Array<PluginAuthMethod>> = null;
		for (hook in hooks) {
			if (hook.provider == provider)
				matched = hook.methods;
		}
		return matched == null ? [] : copyMethods(matched);
	}

	public static function concat(base:Array<PluginAuthHook>, overrides:Array<PluginAuthHook>):Array<PluginAuthHook> {
		final result:Array<PluginAuthHook> = [];
		for (hook in base)
			result.push(hook);
		for (hook in overrides)
			result.push(hook);
		return result;
	}

	static function copyMethods(methods:Array<PluginAuthMethod>):Array<PluginAuthMethod> {
		final result:Array<PluginAuthMethod> = [];
		for (method in methods) {
			final prompts = copyPrompts(method.prompts.orNull());
			if (prompts == null)
				result.push({
					type: method.type,
					label: method.label,
					authorize: copyOptionalAuthorize(method.authorize.orNull()),
				});
			else
				result.push({
					type: method.type,
					label: method.label,
					prompts: prompts,
					authorize: copyOptionalAuthorize(method.authorize.orNull()),
				});
		}
		return result;
	}

	static function copyPrompts(prompts:Null<Array<PluginAuthPrompt>>):Null<Array<PluginAuthPrompt>> {
		if (prompts == null)
			return null;
		final result:Array<PluginAuthPrompt> = [];
		for (prompt in prompts) {
			switch prompt {
				case Text(value):
					result.push(Text({
						key: value.key,
						message: value.message,
						placeholder: copyOptionalString(value.placeholder.orNull()),
						when: copyWhen(value.when.orNull()),
					}));
				case Select(value):
					result.push(Select({
						key: value.key,
						message: value.message,
						options: [for (option in value.options) copyOption(option)],
						when: copyWhen(value.when.orNull()),
					}));
			}
		}
		return result;
	}

	static function copyWhen(when:Null<PluginAuthPromptWhen>):Undefinable<PluginAuthPromptWhen> {
		if (when == null)
			return Undefinable.absent();
		return {
			key: when.key,
			op: when.op,
			value: when.value,
		};
	}

	static function copyOption(option:PluginAuthSelectOption):PluginAuthSelectOption {
		return {
			label: option.label,
			value: option.value,
			hint: copyOptionalString(option.hint.orNull()),
		};
	}

	static function copyOptionalString(value:Null<String>):Undefinable<String> {
		return value == null ? Undefinable.absent() : value;
	}

	static function copyOptionalAuthorize(value:Null<PluginAuthAuthorize>):Undefinable<PluginAuthAuthorize> {
		return value == null ? Undefinable.absent() : value;
	}
}
