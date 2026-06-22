package opencodehx.provider;

import genes.ts.Unknown;
import haxe.DynamicAccess;
import opencodehx.provider.ProviderTypes.ProviderHeaders;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;

/**
 * Narrow reader for provider SDK passthrough options.
 *
 * `ProviderOptions` mirrors upstream's `Record<string, any>` because provider
 * packages and plugins may own arbitrary option keys. Keep the weak reads in
 * this helper, narrow before returning, and pass typed values to loaders.
 */
class ProviderOptionAccess {
	public static function string(options:ProviderOptions, field:String, fallback:Null<String>):Null<String> {
		final value = options.get(field);
		return Std.isOfType(value, String) ? Std.string(value) : fallback;
	}

	public static function bool(options:ProviderOptions, field:String, fallback:Null<Bool>):Null<Bool> {
		final value = options.get(field);
		return Std.isOfType(value, Bool) ? value : fallback;
	}

	public static function numberValue(options:ProviderOptions, field:String, fallback:Null<Float>):Null<Float> {
		final value = options.get(field);
		return Std.isOfType(value, Float) || Std.isOfType(value, Int) ? Std.parseFloat(Std.string(value)) : fallback;
	}

	public static function baseURL(options:ProviderOptions, model:ProviderModel):Null<String> {
		final configured = string(options, "baseURL", null);
		if (configured != null && configured != "")
			return configured;
		return model.api.url;
	}

	public static function headers(options:ProviderOptions, modelHeaders:ProviderHeaders):Null<DynamicAccess<String>> {
		final result = new DynamicAccess<String>();
		copyStringFields(options.get("headers"), result);
		for (field in modelHeaders.keys()) {
			final value = modelHeaders.get(field);
			if (value != null)
				result.set(field, value);
		}
		return empty(result) ? null : result;
	}

	public static function stringMap(options:ProviderOptions, field:String):Null<DynamicAccess<String>> {
		final result = new DynamicAccess<String>();
		copyStringFields(options.get(field), result);
		return empty(result) ? null : result;
	}

	public static function boolMap(options:ProviderOptions, field:String):Null<DynamicAccess<Bool>> {
		final result = new DynamicAccess<Bool>();
		copyBoolFields(options.get(field), result);
		return emptyBool(result) ? null : result;
	}

	public static function unknownRecord(options:ProviderOptions, field:String):Null<DynamicAccess<Unknown>> {
		final result = new DynamicAccess<Unknown>();
		copyUnknownFields(options.get(field), result);
		return emptyUnknown(result) ? null : result;
	}

	static function copyStringFields(source:Dynamic, target:DynamicAccess<String>):Void {
		// Provider option records are intentionally open SDK/plugin boundary data.
		// Reflection is confined here and only string-valued header fields escape.
		if (source == null || !Reflect.isObject(source))
			return;
		if (Std.isOfType(source, Array) || Std.isOfType(source, String) || Std.isOfType(source, Bool) || Std.isOfType(source, Float)
			|| Std.isOfType(source, Int))
			return;
		for (field in Reflect.fields(source)) {
			final value = Reflect.field(source, field);
			if (Std.isOfType(value, String))
				target.set(field, Std.string(value));
		}
	}

	static function copyBoolFields(source:Dynamic, target:DynamicAccess<Bool>):Void {
		// Provider option records are intentionally open SDK/plugin boundary data.
		// Reflection is confined here and only boolean feature flags escape.
		if (source == null || !Reflect.isObject(source))
			return;
		if (Std.isOfType(source, Array) || Std.isOfType(source, String) || Std.isOfType(source, Bool) || Std.isOfType(source, Float)
			|| Std.isOfType(source, Int))
			return;
		for (field in Reflect.fields(source)) {
			final value:Dynamic = Reflect.field(source, field);
			if (Std.isOfType(value, Bool))
				target.set(field, value == true);
		}
	}

	static function copyUnknownFields(source:Dynamic, target:DynamicAccess<Unknown>):Void {
		// Some provider SDKs own open JSON-shaped option records. This helper
		// proves the value is a record before forwarding leaves as Unknown.
		if (source == null || !Reflect.isObject(source))
			return;
		if (Std.isOfType(source, Array) || Std.isOfType(source, String) || Std.isOfType(source, Bool) || Std.isOfType(source, Float)
			|| Std.isOfType(source, Int))
			return;
		for (field in Reflect.fields(source))
			target.set(field, Unknown.fromBoundary(Reflect.field(source, field)));
	}

	static function empty(value:DynamicAccess<String>):Bool {
		for (_ in value.keys())
			return false;
		return true;
	}

	static function emptyBool(value:DynamicAccess<Bool>):Bool {
		for (_ in value.keys())
			return false;
		return true;
	}

	static function emptyUnknown(value:DynamicAccess<Unknown>):Bool {
		for (_ in value.keys())
			return false;
		return true;
	}
}
