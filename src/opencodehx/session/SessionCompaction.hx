package opencodehx.session;

import opencodehx.config.ConfigInfo;
import opencodehx.provider.ProviderTransform;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.TokenUsage;

typedef SessionCompactionCheck = {
	final config:ConfigInfo;
	final model:ProviderModel;
	final tokens:TokenUsage;
}

typedef SessionCompactionResult = {
	final overflow:Bool;
	final usable:Float;
	final count:Float;
}

class SessionCompaction {
	static inline final COMPACTION_BUFFER = 20000;

	public static function check(input:SessionCompactionCheck):SessionCompactionResult {
		final usableTokens = usable(input.config, input.model);
		final countedTokens = count(input.tokens);
		return {
			overflow: isOverflow(input),
			usable: usableTokens,
			count: countedTokens,
		};
	}

	public static function isOverflow(input:SessionCompactionCheck):Bool {
		if (input.config.compaction != null && input.config.compaction.auto == false)
			return false;
		if (input.model.limit.context == 0)
			return false;
		return count(input.tokens) >= usable(input.config, input.model);
	}

	public static function usable(config:ConfigInfo, model:ProviderModel):Float {
		final context = model.limit.context;
		if (context == 0)
			return 0;
		var reserved:Float = Math.min(COMPACTION_BUFFER, ProviderTransform.maxOutputTokens(model));
		final compaction = config.compaction;
		if (compaction != null) {
			final configured = compaction.reserved;
			if (configured != null)
				reserved = configured;
		}
		final inputLimit = model.limit.input;
		if (inputLimit != null)
			return Math.max(0, inputLimit - reserved);
		return Math.max(0, context - ProviderTransform.maxOutputTokens(model));
	}

	public static function count(tokens:TokenUsage):Float {
		if (tokens.total != null && tokens.total != 0)
			return tokens.total;
		return tokens.input + tokens.output + tokens.cache.read + tokens.cache.write;
	}

	public static function part(sessionID:SessionID, messageID:MessageID, partID:PartID, auto:Bool, overflow:Bool):Part {
		return CompactionPart({
			id: partID,
			sessionID: sessionID,
			messageID: messageID,
			type: "compaction",
			auto: auto,
			overflow: overflow,
		});
	}
}
