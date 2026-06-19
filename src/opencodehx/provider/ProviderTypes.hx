package opencodehx.provider;

import genes.ts.Unknown;
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
	final cache:ProviderCostCache;
	@:optional var experimentalOver200K:ProviderOver200KCost;
}

typedef ProviderCostCache = {
	final read:Float;
	final write:Float;
}

typedef ProviderOver200KCost = {
	final input:Float;
	final output:Float;
	final cache:ProviderCostCache;
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
typedef ProviderVariants = DynamicAccess<ProviderOptions>;
typedef ProviderJsonSchemaProperties = DynamicAccess<ProviderJsonSchema>;

typedef ProviderJsonSchema = {
	@:optional var type:String;
	@:optional var properties:ProviderJsonSchemaProperties;
	@:optional var patternProperties:ProviderJsonSchemaProperties;
	@:optional var required:Array<String>;
	@:optional var items:ProviderJsonSchema;
	@:optional var prefixItems:Array<ProviderJsonSchema>;
	@:optional var anyOf:Array<ProviderJsonSchema>;
	@:optional var oneOf:Array<ProviderJsonSchema>;
	@:optional var allOf:Array<ProviderJsonSchema>;
	@:optional var not:ProviderJsonSchema;
	@:optional var additionalProperties:Bool;
	// JSON Schema enum values are arbitrary literals. Keep Dynamic confined to
	// this schema-boundary field and normalize/narrow before application use.
	@:native("enum") @:optional var enumValues:Array<Dynamic>;
}

enum abstract ProviderMessageRole(String) from String to String {
	final System = "system";
	final User = "user";
	final Assistant = "assistant";
	final Tool = "tool";
}

enum abstract ProviderMessagePartType(String) from String to String {
	final Text = "text";
	final Reasoning = "reasoning";
	final Image = "image";
	final File = "file";
	final ToolCall = "tool-call";
	final ToolResult = "tool-result";
	final ToolApprovalRequest = "tool-approval-request";
	final ToolApprovalResponse = "tool-approval-response";
}

typedef ProviderMessagePart = {
	final type:ProviderMessagePartType;
	@:optional var text:String;
	@:optional var image:String;
	@:optional var mediaType:String;
	@:optional var filename:String;
	@:optional var toolCallId:String;
	@:optional var toolName:String;
	@:optional var input:Unknown;
	@:optional var output:Unknown;
	@:optional var providerOptions:ProviderOptions;
}

typedef ProviderMessageContent = EitherType<String, Array<ProviderMessagePart>>;

typedef ProviderMessage = {
	final role:ProviderMessageRole;
	var content:ProviderMessageContent;
	@:optional var providerOptions:ProviderOptions;
}

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

typedef ModelsDevCost = {
	final input:Float;
	final output:Float;
	@:optional final cache_read:Float;
	@:optional final cache_write:Float;
	@:optional final context_over_200k:ModelsDevOver200KCost;
}

typedef ModelsDevOver200KCost = {
	final input:Float;
	final output:Float;
	@:optional final cache_read:Float;
	@:optional final cache_write:Float;
}

typedef ModelsDevLimit = {
	final context:Float;
	@:optional final input:Float;
	final output:Float;
}

typedef ModelsDevModalities = {
	final input:Array<String>;
	final output:Array<String>;
}

typedef ModelsDevProviderApi = {
	@:optional final npm:String;
	@:optional final api:String;
}

typedef ModelsDevModeProvider = {
	@:optional final body:DynamicAccess<Unknown>;
	@:optional final headers:DynamicAccess<String>;
}

typedef ModelsDevMode = {
	@:optional final cost:ModelsDevCost;
	@:optional final provider:ModelsDevModeProvider;
}

typedef ModelsDevExperimental = {
	@:optional final modes:DynamicAccess<ModelsDevMode>;
}

typedef ModelsDevModel = {
	final id:String;
	final name:String;
	@:optional final family:String;
	@:optional final release_date:String;
	@:optional final attachment:Bool;
	@:optional final reasoning:Bool;
	@:optional final temperature:Bool;
	@:optional final tool_call:Bool;
	@:optional final interleaved:ProviderInterleaved;
	@:optional final cost:ModelsDevCost;
	final limit:ModelsDevLimit;
	@:optional final modalities:ModelsDevModalities;
	@:optional final experimental:ModelsDevExperimental;
	@:optional final status:String;
	@:optional final provider:ModelsDevProviderApi;
}

typedef ModelsDevProvider = {
	final id:String;
	final name:String;
	@:optional final env:Array<String>;
	@:optional final api:String;
	@:optional final npm:String;
	final models:DynamicAccess<ModelsDevModel>;
}
