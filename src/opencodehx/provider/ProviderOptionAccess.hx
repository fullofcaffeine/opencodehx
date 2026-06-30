package opencodehx.provider;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.DynamicAccess;
import opencodehx.provider.ProviderTypes.ProviderHeaders;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;

/**
 * Narrow reader for provider SDK passthrough options.
 *
 * `ProviderOptions` mirrors upstream's `Record<string, any>` because provider
 * packages and plugins may own arbitrary option keys. Keep the weak reads in
 * this helper, narrow unknown records before returning, and pass typed values
 * to loaders.
 */
class ProviderOptionAccess {
	public static function string(options:ProviderOptions, field:String, fallback:Null<String>):Null<String> {
		final value = UnknownNarrow.string(option(options, field));
		return value == null ? fallback : value;
	}

	public static function bool(options:ProviderOptions, field:String, fallback:Null<Bool>):Null<Bool> {
		final value = UnknownNarrow.bool(option(options, field));
		return value == null ? fallback : value;
	}

	public static function numberValue(options:ProviderOptions, field:String, fallback:Null<Float>):Null<Float> {
		final value = UnknownNarrow.number(option(options, field));
		return value == null ? fallback : value;
	}

	public static function baseURL(options:ProviderOptions, model:ProviderModel):Null<String> {
		final configured = string(options, "baseURL", null);
		if (configured != null && configured != "")
			return configured;
		return model.api.url;
	}

	public static function headers(options:ProviderOptions, modelHeaders:ProviderHeaders):Null<DynamicAccess<String>> {
		final result = new DynamicAccess<String>();
		copyStringFields(option(options, "headers"), result);
		for (field in modelHeaders.keys()) {
			final value = modelHeaders.get(field);
			if (value != null)
				result.set(field, value);
		}
		return empty(result) ? null : result;
	}

	public static function stringMap(options:ProviderOptions, field:String):Null<DynamicAccess<String>> {
		final result = new DynamicAccess<String>();
		copyStringFields(option(options, field), result);
		return empty(result) ? null : result;
	}

	public static function boolMap(options:ProviderOptions, field:String):Null<DynamicAccess<Bool>> {
		final result = new DynamicAccess<Bool>();
		copyBoolFields(option(options, field), result);
		return empty(result) ? null : result;
	}

	public static function unknownRecord(options:ProviderOptions, field:String):Null<DynamicAccess<Unknown>> {
		final result = new DynamicAccess<Unknown>();
		copyUnknownFields(option(options, field), result);
		return empty(result) ? null : result;
	}

	static inline function option(options:ProviderOptions, field:String):Unknown {
		return Unknown.fromBoundary(options.get(field));
	}

	static function copyStringFields(source:Unknown, target:DynamicAccess<String>):Void {
		final record = UnknownNarrow.record(source);
		if (record == null)
			return;
		for (field in record.keys()) {
			final value = UnknownNarrow.string(record.get(field));
			if (value != null)
				target.set(field, value);
		}
	}

	static function copyBoolFields(source:Unknown, target:DynamicAccess<Bool>):Void {
		final record = UnknownNarrow.record(source);
		if (record == null)
			return;
		for (field in record.keys()) {
			final value = UnknownNarrow.bool(record.get(field));
			if (value != null)
				target.set(field, value);
		}
	}

	static function copyUnknownFields(source:Unknown, target:DynamicAccess<Unknown>):Void {
		final record = UnknownNarrow.record(source);
		if (record == null)
			return;
		for (field in record.keys())
			target.set(field, record.get(field));
	}

	static function empty<T>(value:DynamicAccess<T>):Bool {
		for (_ in value.keys())
			return false;
		return true;
	}
}
