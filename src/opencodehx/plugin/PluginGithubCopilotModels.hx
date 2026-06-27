package opencodehx.plugin;

import opencodehx.provider.ProviderOpenRecords;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderCapabilities;
import opencodehx.provider.ProviderTypes.ProviderIDs;
import opencodehx.provider.ProviderTypes.ProviderModel;

using StringTools;

typedef CopilotRemoteModel = {
	final modelPickerEnabled:Bool;
	final id:String;
	final name:String;
	final version:String;
	final family:String;
	final maxContextWindowTokens:Float;
	final maxOutputTokens:Float;
	final maxPromptTokens:Float;
	final streaming:Bool;
	final toolCalls:Bool;
	@:optional final supportedEndpoints:Array<String>;
	@:optional final policyState:String;
	@:optional final adaptiveThinking:Bool;
	@:optional final reasoningEffort:Array<String>;
	@:optional final maxThinkingBudget:Float;
	@:optional final minThinkingBudget:Float;
	@:optional final vision:Bool;
	@:optional final visionSupportedMediaTypes:Array<String>;
}

class PluginGithubCopilotModels {
	static inline final DEFAULT_BASE_URL = "https://api.githubcopilot.com";
	static inline final SDK_NPM = "@ai-sdk/github-copilot";
	static inline final ANTHROPIC_NPM = "@ai-sdk/anthropic";

	public static function merge(baseURL:String, remoteModels:Array<CopilotRemoteModel>, existing:Map<String, ProviderModel>):Map<String, ProviderModel> {
		final result = copyModels(existing);
		final remote = new Map<String, CopilotRemoteModel>();
		for (model in remoteModels) {
			if (model.modelPickerEnabled && model.policyState != "disabled")
				remote.set(model.id, model);
		}

		final existingKeys = [for (key in result.keys()) key];
		for (key in existingKeys) {
			final current = result.get(key);
			final next = remote.get(current.api.id);
			if (next == null) {
				result.remove(key);
			} else {
				result.set(key, build(key, next, baseURL, current));
			}
		}

		for (id in remote.keys()) {
			if (!result.exists(id))
				result.set(id, build(id, remote.get(id), baseURL, null));
		}

		return result;
	}

	public static function fallbackModels(existing:Map<String, ProviderModel>, ?enterpriseUrl:String):Map<String, ProviderModel> {
		final url = baseURL(enterpriseUrl);
		final result = new Map<String, ProviderModel>();
		for (key in existing.keys()) {
			result.set(key, fix(existing.get(key), url));
		}
		return result;
	}

	public static function baseURL(?enterpriseUrl:String):String {
		if (enterpriseUrl == null || enterpriseUrl == "")
			return DEFAULT_BASE_URL;
		return "https://copilot-api." + normalizeDomain(enterpriseUrl);
	}

	static function normalizeDomain(url:String):String {
		var out = url;
		if (out.startsWith("https://"))
			out = out.substr("https://".length);
		else if (out.startsWith("http://"))
			out = out.substr("http://".length);
		while (out.endsWith("/")) {
			out = out.substr(0, out.length - 1);
		}
		return out;
	}

	static function build(key:String, remote:CopilotRemoteModel, url:String, prev:Null<ProviderModel>):ProviderModel {
		final messagesAPI = includes(remote.supportedEndpoints, "/v1/messages");
		final apiUrl = messagesAPI ? url + "/v1" : url;
		final apiNpm = messagesAPI ? ANTHROPIC_NPM : SDK_NPM;
		final capabilities = capabilities(remote, prev);
		return {
			id: ModelID.make(key),
			providerID: ProviderIDs.known("github-copilot"),
			api: {
				id: remote.id,
				url: apiUrl,
				npm: apiNpm,
			},
			name: prev == null ? remote.name : prev.name,
			family: prev == null ? remote.family : prev.family,
			capabilities: capabilities,
			cost: {
				input: 0,
				output: 0,
				cache: {
					read: 0,
					write: 0,
				},
			},
			limit: {
				context: remote.maxContextWindowTokens,
				input: remote.maxPromptTokens,
				output: remote.maxOutputTokens,
			},
			options: prev == null ? ProviderOpenRecords.options() : prev.options,
			headers: prev == null ? ProviderOpenRecords.headers() : prev.headers,
			release_date: prev == null ? releaseDate(remote) : prev.release_date,
			variants: prev == null ? ProviderOpenRecords.variants() : prev.variants,
			status: "active",
		};
	}

	static function fix(model:ProviderModel, url:String):ProviderModel {
		return {
			id: model.id,
			providerID: model.providerID,
			api: {
				id: model.api.id,
				url: url,
				npm: SDK_NPM,
			},
			name: model.name,
			family: model.family,
			capabilities: model.capabilities,
			cost: model.cost,
			limit: model.limit,
			options: model.options,
			headers: model.headers,
			release_date: model.release_date,
			variants: model.variants,
			status: model.status,
		};
	}

	static function capabilities(remote:CopilotRemoteModel, prev:Null<ProviderModel>):ProviderCapabilities {
		return {
			temperature: prev == null ? true : prev.capabilities.temperature,
			reasoning: prev == null ? reasoning(remote) : prev.capabilities.reasoning,
			attachment: prev == null ? true : prev.capabilities.attachment,
			toolcall: remote.toolCalls,
			input: {
				text: true,
				audio: false,
				image: image(remote),
				video: false,
				pdf: false,
			},
			output: {
				text: true,
				audio: false,
				image: false,
				video: false,
				pdf: false,
			},
			interleaved: false,
		};
	}

	static function reasoning(remote:CopilotRemoteModel):Bool {
		return remote.adaptiveThinking == true
			|| (remote.reasoningEffort != null && remote.reasoningEffort.length > 0)
			|| remote.maxThinkingBudget != null
			|| remote.minThinkingBudget != null;
	}

	static function image(remote:CopilotRemoteModel):Bool {
		if (remote.vision == true)
			return true;
		if (remote.visionSupportedMediaTypes == null)
			return false;
		for (mediaType in remote.visionSupportedMediaTypes) {
			if (mediaType.startsWith("image/"))
				return true;
		}
		return false;
	}

	static function releaseDate(remote:CopilotRemoteModel):String {
		final prefix = remote.id + "-";
		return remote.version.startsWith(prefix) ? remote.version.substr(prefix.length) : remote.version;
	}

	static function includes(values:Null<Array<String>>, expected:String):Bool {
		if (values == null)
			return false;
		for (value in values) {
			if (value == expected)
				return true;
		}
		return false;
	}

	static function copyModels(existing:Map<String, ProviderModel>):Map<String, ProviderModel> {
		final result = new Map<String, ProviderModel>();
		for (key in existing.keys()) {
			result.set(key, existing.get(key));
		}
		return result;
	}
}
