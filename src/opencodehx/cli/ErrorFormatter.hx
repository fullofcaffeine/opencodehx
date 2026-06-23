package opencodehx.cli;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import opencodehx.account.AccountError.AccountServiceError;
import opencodehx.account.AccountError.AccountTransportError;
import opencodehx.config.ConfigError.ConfigException;
import opencodehx.config.ConfigError.ConfigFailure;
import opencodehx.provider.ProviderError.ProviderException;
import opencodehx.provider.ProviderError.ProviderFailure;
import opencodehx.util.ErrorTools;

class ErrorFormatter {
	public static function format(input:Unknown):String {
		if (Std.isOfType(input, AccountTransportError) || Std.isOfType(input, AccountServiceError))
			return ErrorTools.message(input);
		final tagged = taggedMessage(input);
		if (tagged != null)
			return tagged;

		if (Std.isOfType(input, ProviderException)) {
			final error:ProviderException = cast input;
			return provider(error.failure);
		}

		if (Std.isOfType(input, ConfigException)) {
			final error:ConfigException = cast input;
			return config(error.failure);
		}

		return ErrorTools.format(input);
	}

	public static function formatUnknown(input:Unknown):String {
		return ErrorTools.format(input);
	}

	static function taggedMessage(input:Unknown):Null<String> {
		final record = UnknownNarrow.record(input);
		if (record == null)
			return null;
		final tag = UnknownNarrow.string(record.get("_tag"));
		if (tag != "AccountServiceError" && tag != "AccountTransportError")
			return null;
		final message = UnknownNarrow.string(record.get("message"));
		return message == null ? "" : message;
	}

	static function provider(failure:ProviderFailure):String {
		return switch failure {
			case ModelNotFound(providerID, modelID, suggestions):
				final lines = ['Model not found: ${providerID.toString()}/${modelID.toString()}'];
				if (suggestions.length > 0)
					lines.push("Did you mean: " + suggestions.join(", "));
				lines.push("Try: `opencode models` to list available models");
				lines.push("Or check your config (opencode.json) provider/model names");
				lines.join("\n");
			case NoProviders:
				"No providers found";
		}
	}

	static function config(failure:ConfigFailure):String {
		return switch failure {
			case JsonError(path, message):
				'Config file at ${path} is not valid JSON(C)' + (message == "" ? "" : ': ${message}');
			case InvalidError(path, issues):
				final suffix = path != "" && path != "config" ? ' at ${path}' : "";
				final lines = ['Configuration is invalid${suffix}'];
				for (issue in issues)
					lines.push("↳ " + issue);
				lines.join("\n");
			case IoError(path, message):
				'Could not read config file at ${path}' + (message == "" ? "" : ': ${message}');
		}
	}
}
