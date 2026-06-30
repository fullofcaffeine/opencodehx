package opencodehx.server;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import opencodehx.server.ServerProtocol.CreateSessionRequest;
import opencodehx.server.ServerProtocol.DecodeResult;
import opencodehx.server.ServerProtocol.SelectSessionRequest;
import opencodehx.server.ServerProtocol.UpdateSessionRequest;

using StringTools;

/**
 * Decodes session route request bodies at the Hono `unknown` JSON boundary.
 *
 * `ServerProtocol` also owns macro-checked event names, so this runtime module
 * keeps JS narrowing helpers out of that macro-heavy file.
 */
class ServerSessionProtocol {
	public static function decodeCreate(raw:Unknown):DecodeResult<CreateSessionRequest> {
		return switch optionalString(raw, "prompt") {
			case Rejected(message):
				Rejected(message);
			case Decoded(rawPrompt):
				final prompt = emptyToDefault(rawPrompt, ServerProtocol.DEFAULT_PROMPT);
				switch optionalString(raw, "title") {
					case Rejected(message):
						Rejected(message);
					case Decoded(rawTitle):
						switch optionalString(raw, "parentID") {
							case Rejected(message):
								Rejected(message);
							case Decoded(parentID):
								final parentIDValid = parentID == null || parentID.startsWith("ses_");
								if (!parentIDValid) Rejected("Invalid parent session ID"); else Decoded({
									prompt: prompt,
									title: emptyToDefault(rawTitle, prompt),
									parentID: parentID,
								});
						}
				}
		}
	}

	public static function decodeSelect(raw:Unknown):DecodeResult<SelectSessionRequest> {
		return switch optionalString(raw, "sessionID") {
			case Rejected(_):
				Rejected("Invalid session ID");
			case Decoded(value):
				if (value == null || !value.startsWith("ses_")) Rejected("Invalid session ID"); else Decoded({sessionID: value});
		}
	}

	public static function decodeUpdate(raw:Unknown):DecodeResult<UpdateSessionRequest> {
		return switch optionalString(raw, "title") {
			case Rejected(message):
				Rejected(message);
			case Decoded(title):
				switch optionalNestedFloat(raw, "time", "archived") {
					case Rejected(message):
						Rejected(message);
					case Decoded(archived):
						Decoded({title: title, archived: archived});
				}
		}
	}

	static function optionalString(raw:Unknown, field:String):DecodeResult<Null<String>> {
		final record = UnknownNarrow.record(raw);
		if (record == null || !record.hasOwn(field))
			return Decoded(null);
		final value = record.get(field);
		if (isAbsent(value))
			return Decoded(null);
		final stringValue = UnknownNarrow.string(value);
		return stringValue == null ? Rejected('${field}: expected string') : Decoded(stringValue);
	}

	static function optionalNestedFloat(raw:Unknown, parent:String, field:String):DecodeResult<Null<Float>> {
		final record = UnknownNarrow.record(raw);
		if (record == null || !record.hasOwn(parent))
			return Decoded(null);
		final parentValue = record.get(parent);
		if (isAbsent(parentValue))
			return Decoded(null);
		final nested = UnknownNarrow.record(parentValue);
		if (nested == null)
			return Rejected('${parent}: expected object');
		if (!nested.hasOwn(field))
			return Decoded(null);
		final value = nested.get(field);
		if (isAbsent(value))
			return Decoded(null);
		final parsed = number(value);
		return parsed == null ? Rejected('${parent}.${field}: expected number') : Decoded(parsed);
	}

	static function number(value:Unknown):Null<Float> {
		final parsed = UnknownNarrow.number(value);
		return parsed == null || Math.isNaN(parsed) ? null : parsed;
	}

	static function emptyToDefault(value:Null<String>, fallback:String):String {
		if (value == null || value.trim() == "")
			return fallback;
		return value;
	}

	static inline function isAbsent(value:Unknown):Bool {
		return UnknownNarrow.isNull(value) || UnknownNarrow.isUndefined(value);
	}
}
