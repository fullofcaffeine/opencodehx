package opencodehx.plugin;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.Json;
import opencodehx.host.node.NodeBuffer;

typedef CodexTokenSet = {
	@:optional final id_token:String;
	@:optional final access_token:String;
	@:optional final refresh_token:String;
}

class PluginCodex {
	static inline final AuthClaimNamespace = "https://api.openai.com/auth";

	public static function parseJwtClaims(token:String):Null<Unknown> {
		final parts = token.split(".");
		if (parts.length < 3)
			return null;
		try {
			return Unknown.fromBoundary(Json.parse(NodeBuffer.fromBase64Url(parts[1])));
		} catch (_:Dynamic) {
			return null;
		}
	}

	public static function extractAccountIdFromClaims(claims:Unknown):Null<String> {
		final record = UnknownNarrow.record(claims);
		if (record == null)
			return null;

		final root = nonEmptyString(record.get("chatgpt_account_id"));
		if (root != null)
			return root;

		final nested = UnknownNarrow.record(record.get(AuthClaimNamespace));
		if (nested != null) {
			final nestedID = nonEmptyString(nested.get("chatgpt_account_id"));
			if (nestedID != null)
				return nestedID;
		}

		final organizations = UnknownNarrow.array(record.get("organizations"));
		if (organizations != null && organizations.length > 0) {
			final first = UnknownNarrow.record(organizations.get(0));
			if (first != null)
				return nonEmptyString(first.get("id"));
		}
		return null;
	}

	public static function extractAccountId(tokens:CodexTokenSet):Null<String> {
		final idToken = extractTokenAccountId(tokens.id_token);
		if (idToken != null)
			return idToken;
		return extractTokenAccountId(tokens.access_token);
	}

	static function extractTokenAccountId(token:Null<String>):Null<String> {
		if (token == null || token == "")
			return null;
		final claims = parseJwtClaims(token);
		if (claims == null)
			return null;
		return extractAccountIdFromClaims(claims);
	}

	static function nonEmptyString(value:Unknown):Null<String> {
		final text = UnknownNarrow.string(value);
		if (text == null || text == "")
			return null;
		return text;
	}
}
