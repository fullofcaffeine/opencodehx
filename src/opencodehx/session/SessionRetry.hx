package opencodehx.session;

import haxe.DynamicAccess;
import haxe.Json;
import opencodehx.host.Clock;

using StringTools;

typedef SessionApiError = {
	final message:String;
	final isRetryable:Bool;
	@:optional final statusCode:Int;
	@:optional final responseBody:String;
	@:optional final responseHeaders:DynamicAccess<String>;
}

typedef SessionContextOverflowError = {
	final message:String;
	@:optional final responseBody:String;
}

enum SessionProviderError {
	Api(error:SessionApiError);
	ContextOverflow(error:SessionContextOverflowError);
	Message(message:String);
}

typedef SessionRetryStatus = {
	final attempt:Int;
	final message:String;
	final nextDelay:Float;
}

typedef SessionRetryErrorRecord = {
	final name:String;
	final message:String;
	final isRetryable:Null<Bool>;
	final statusCode:Null<Int>;
	final responseBody:Null<String>;
}

class SessionRetry {
	public static inline final GO_UPSELL_MESSAGE = "Free usage exceeded, subscribe to Go https://opencode.ai/go";
	public static inline final RETRY_INITIAL_DELAY = 2000;
	public static inline final RETRY_BACKOFF_FACTOR = 2;
	public static inline final RETRY_MAX_DELAY_NO_HEADERS = 30000;
	public static inline final RETRY_MAX_DELAY = 2147483647;

	public static function delay(attempt:Int, ?error:SessionApiError, ?nowMillis:Float):Float {
		if (error != null) {
			final headers = error.responseHeaders;
			if (headers != null) {
				final retryAfterMs = headers.get("retry-after-ms");
				if (retryAfterMs != null) {
					final parsedMs = Std.parseFloat(retryAfterMs);
					if (!Math.isNaN(parsedMs))
						return cap(parsedMs);
				}

				final retryAfter = headers.get("retry-after");
				if (retryAfter != null) {
					final parsedSeconds = Std.parseFloat(retryAfter);
					if (!Math.isNaN(parsedSeconds))
						return cap(Math.ceil(parsedSeconds * 1000));
					final now = nowMillis == null ? currentTimeMillis() : nowMillis;
					final parsedDate = parseHttpDateMillis(retryAfter) - now;
					if (!Math.isNaN(parsedDate) && parsedDate > 0)
						return cap(Math.ceil(parsedDate));
				}

				return cap(exponential(attempt));
			}
		}
		return cap(Math.min(exponential(attempt), RETRY_MAX_DELAY_NO_HEADERS));
	}

	public static function retryable(error:SessionProviderError):Null<String> {
		return switch error {
			case ContextOverflow(_):
				null;
			case Api(api):
				retryableApi(api);
			case Message(message):
				retryableText(message);
		}
	}

	public static function status(error:SessionProviderError, attempt:Int, ?nowMillis:Float):Null<SessionRetryStatus> {
		final message = retryable(error);
		if (message == null)
			return null;
		return {
			attempt: attempt,
			message: message,
			nextDelay: delay(attempt, api(error), nowMillis),
		};
	}

	public static function api(error:SessionProviderError):Null<SessionApiError> {
		return switch error {
			case Api(apiError): apiError;
			case _: null;
		}
	}

	public static function errorRecord(error:SessionProviderError):SessionRetryErrorRecord {
		return switch error {
			case Api(api):
				{
					name: "APIError",
					message: api.message,
					isRetryable: api.isRetryable,
					statusCode: api.statusCode,
					responseBody: api.responseBody,
				};
			case ContextOverflow(context):
				{
					name: "ContextOverflowError",
					message: context.message,
					isRetryable: false,
					statusCode: null,
					responseBody: context.responseBody,
				};
			case Message(message):
				{
					name: "Error",
					message: message,
					isRetryable: null,
					statusCode: null,
					responseBody: null
				};
		}
	}

	static function retryableApi(error:SessionApiError):Null<String> {
		final status = error.statusCode;
		if (!error.isRetryable && !(status != null && status >= 500))
			return null;
		if (error.responseBody != null && error.responseBody.indexOf("FreeUsageLimitError") != -1)
			return GO_UPSELL_MESSAGE;
		return error.message.indexOf("Overloaded") != -1 ? "Provider is overloaded" : error.message;
	}

	static function retryableText(message:String):Null<String> {
		final lower = message.toLowerCase();
		if (lower.indexOf("rate increased too quickly") != -1
			|| lower.indexOf("rate limit") != -1
			|| lower.indexOf("too many requests") != -1)
			return message;
		return retryableJson(message);
	}

	static function retryableJson(message:String):Null<String> {
		final parsed = parseJsonObject(message);
		if (parsed == null)
			return null;
		if (stringAt(parsed, ["type"]) == "error" && stringAt(parsed, ["error", "type"]) == "too_many_requests")
			return "Too Many Requests";
		final code = stringAt(parsed, ["code"]);
		if (code != null && (code.indexOf("exhausted") != -1 || code.indexOf("unavailable") != -1))
			return "Provider is overloaded";
		final errorCode = stringAt(parsed, ["error", "code"]);
		if (stringAt(parsed, ["type"]) == "error" && errorCode != null && errorCode.indexOf("rate_limit") != -1)
			return "Rate Limited";
		return null;
	}

	static function parseJsonObject(message:String):Null<Dynamic> {
		try {
			// haxe.Json returns Dynamic because JSON is an untyped runtime
			// boundary. Access stays inside stringAt(), which checks field
			// presence and string shape before returning typed data.
			final parsed:Dynamic = Json.parse(message);
			return parsed;
		} catch (_:Dynamic) {
			return null;
		}
	}

	static function stringAt(data:Dynamic, path:Array<String>):Null<String> {
		// Dynamic is contained to walking parsed JSON by field name. The final
		// cast happens only after Std.isOfType proves the leaf is a String.
		var current:Dynamic = data;
		for (field in path) {
			if (current == null || !Reflect.hasField(current, field))
				return null;
			current = Reflect.field(current, field);
		}
		return Std.isOfType(current, String) ? cast current : null;
	}

	static function exponential(attempt:Int):Float {
		return RETRY_INITIAL_DELAY * Math.pow(RETRY_BACKOFF_FACTOR, attempt - 1);
	}

	static function cap(ms:Float):Float {
		return Math.min(ms, RETRY_MAX_DELAY);
	}

	static function currentTimeMillis():Float {
		return Clock.nowMillis();
	}

	static function parseHttpDateMillis(value:String):Float {
		return Clock.parseHttpDateMillis(value);
	}
}
