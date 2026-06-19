package opencodehx.provider;

import haxe.extern.EitherType;
import haxe.DynamicAccess;

abstract ProviderID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):ProviderID {
		return new ProviderID(value);
	}

	public inline function toString():String {
		return this;
	}
}

abstract ModelID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):ModelID {
		return new ModelID(value);
	}

	public inline function toString():String {
		return this;
	}
}

typedef ProviderCapabilityIO = {
	final text:Bool;
	final image:Bool;
	final audio:Bool;
	final video:Bool;
	final pdf:Bool;
}

enum abstract ProviderInterleavedField(String) from String to String {
	final ReasoningContent = "reasoning_content";
	final ReasoningDetails = "reasoning_details";
}

typedef ProviderInterleavedConfig = {
	final field:ProviderInterleavedField;
}

typedef ProviderInterleaved = EitherType<Bool, ProviderInterleavedConfig>;

typedef ProviderCapabilities = {
	final toolcall:Bool;
	final attachment:Bool;
	final reasoning:Bool;
	final temperature:Bool;
	final interleaved:ProviderInterleaved;
	final input:ProviderCapabilityIO;
	final output:ProviderCapabilityIO;
}

typedef ProviderCost = {
	final input:Float;
	final output:Float;
	final cache:{
		final read:Float;
		final write:Float;
	};
}

typedef ProviderLimit = {
	final context:Float;
	@:optional final input:Float;
	final output:Float;
}

typedef ProviderApiInfo = {
	final id:String;
	final url:String;
	final npm:String;
}

// Boundary debt: provider options are SDK-owned passthrough data. Upstream uses
// Record<string, any> here and runtime custom loaders may add functions such as
// fetch or credentialProvider. Keep this confined to provider/factory seams and
// narrow stable provider-specific options into typed facades as those slices land.
typedef ProviderOptions = DynamicAccess<Dynamic>;
typedef ProviderHeaders = DynamicAccess<String>;
typedef ProviderVariants = DynamicAccess<DynamicAccess<Dynamic>>;

typedef ProviderModel = {
	final id:ModelID;
	final providerID:ProviderID;
	final name:String;
	final capabilities:ProviderCapabilities;
	final api:ProviderApiInfo;
	final cost:ProviderCost;
	final limit:ProviderLimit;
	final status:String;
	final options:ProviderOptions;
	final headers:ProviderHeaders;
	final release_date:String;
	final variants:ProviderVariants;
	@:optional final family:String;
}

typedef ProviderInfo = {
	final id:ProviderID;
	final name:String;
	final source:String;
	final env:Array<String>;
	@:optional final key:String;
	final options:ProviderOptions;
	final models:Map<String, ProviderModel>;
}

typedef ParsedModelRef = {
	final providerID:ProviderID;
	final modelID:ModelID;
}
