package opencodehx.session;

import genes.ts.Json;
import genes.ts.JsonValue;
import opencodehx.tool.ToolTypes.ToolCallInput;
#if macro
import haxe.macro.Expr;
#end

abstract MessageJson(JsonValue) from JsonValue to JsonValue {
	inline function new(value:JsonValue) {
		this = value;
	}

	@:from public static inline function fromJson(value:JsonValue):MessageJson {
		return new MessageJson(value);
	}

	public static macro function checked(expr:Expr):Expr {
		return macro @:pos(expr.pos) opencodehx.session.MessageTypes.MessageJson.fromJson(genes.ts.Json.value($expr));
	}

	public static inline function emptyObject():MessageJson {
		return new MessageJson(Json.object({}));
	}
}

abstract ToolStateMetadata(JsonValue) from JsonValue to JsonValue {
	inline function new(value:JsonValue) {
		this = value;
	}

	@:from public static inline function fromJson(value:JsonValue):ToolStateMetadata {
		return new ToolStateMetadata(value);
	}

	public static macro function checked(expr:Expr):Expr {
		return macro @:pos(expr.pos) opencodehx.session.MessageTypes.ToolStateMetadata.fromJson(genes.ts.Json.value($expr));
	}

	public static inline function empty():ToolStateMetadata {
		return new ToolStateMetadata(Json.object({}));
	}
}

typedef CreatedTime = {
	final created:Float;
	@:optional final completed:Float;
}

typedef TimeRange = {
	final start:Float;
	@:optional final end:Float;
}

typedef ToolTimeRange = {
	final start:Float;
	final end:Float;
	@:optional final compacted:Float;
}

typedef TokenCache = {
	final read:Float;
	final write:Float;
}

typedef TokenUsage = {
	@:optional final total:Float;
	final input:Float;
	final output:Float;
	final reasoning:Float;
	final cache:TokenCache;
}

typedef TextSelection = {
	final value:String;
	final start:Int;
	final end:Int;
}

typedef FileSourceData = {
	final text:TextSelection;
	final path:String;
}

typedef SymbolSourceData = {
	final text:TextSelection;
	final path:String;
	final range:MessageJson;
	final name:String;
	final kind:Int;
}

typedef ResourceSourceData = {
	final text:TextSelection;
	final clientName:String;
	final uri:String;
}

enum FilePartSource {
	FileSource(data:FileSourceData);
	SymbolSource(data:SymbolSourceData);
	ResourceSource(data:ResourceSourceData);
}

enum OutputFormat {
	OutputText;
	OutputJsonSchema(schema:MessageJson, retryCount:Int);
}

typedef UserModelSelection = {
	final providerID:String;
	final modelID:String;
	@:optional final variant:String;
}

typedef UserSummary = {
	@:optional final title:String;
	@:optional final body:String;
	final diffs:MessageJson;
}

typedef UserMessage = {
	final id:MessageID;
	final sessionID:SessionID;
	final role:String;
	final time:CreatedTime;
	@:optional final format:OutputFormat;
	@:optional final summary:UserSummary;
	final agent:String;
	final model:UserModelSelection;
	@:optional final system:String;
	@:optional final tools:MessageJson;
}

typedef AssistantPath = {
	final cwd:String;
	final root:String;
}

typedef AssistantMessage = {
	final id:MessageID;
	final sessionID:SessionID;
	final role:String;
	final time:CreatedTime;
	@:optional final error:MessageJson;
	final parentID:MessageID;
	final modelID:String;
	final providerID:String;
	final mode:String;
	final agent:String;
	final path:AssistantPath;
	@:optional final summary:Bool;
	final cost:Float;
	final tokens:TokenUsage;
	@:optional final structured:MessageJson;
	@:optional final variant:String;
	@:optional final finish:String;
}

enum Info {
	UserInfo(data:UserMessage);
	AssistantInfo(data:AssistantMessage);
}

typedef SnapshotPartData = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
	final type:String;
	final snapshot:String;
}

typedef PatchPartData = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
	final type:String;
	final hash:String;
	final files:Array<String>;
}

typedef TextPartData = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
	final type:String;
	final text:String;
	@:optional final synthetic:Bool;
	@:optional final ignored:Bool;
	@:optional final time:TimeRange;
	@:optional final metadata:MessageJson;
}

typedef ReasoningPartData = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
	final type:String;
	final text:String;
	@:optional final metadata:MessageJson;
	final time:TimeRange;
}

typedef FilePartData = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
	final type:String;
	final mime:String;
	@:optional final filename:String;
	final url:String;
	@:optional final source:FilePartSource;
}

typedef AgentPartData = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
	final type:String;
	final name:String;
	@:optional final source:TextSelection;
}

typedef CompactionPartData = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
	final type:String;
	final auto:Bool;
	@:optional final overflow:Bool;
	@:optional final tail_start_id:MessageID;
}

typedef SubtaskModelSelection = {
	final providerID:String;
	final modelID:String;
}

typedef SubtaskPartData = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
	final type:String;
	final prompt:String;
	final description:String;
	final agent:String;
	@:optional final model:SubtaskModelSelection;
	@:optional final command:String;
}

typedef RetryPartData = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
	final type:String;
	final attempt:Float;
	final error:MessageJson;
	final time:CreatedTime;
}

typedef StepStartPartData = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
	final type:String;
	@:optional final snapshot:String;
}

typedef StepFinishPartData = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
	final type:String;
	final reason:String;
	@:optional final snapshot:String;
	final cost:Float;
	final tokens:TokenUsage;
}

typedef ToolStatePendingData = {
	final status:String;
	final input:ToolCallInput;
	final raw:String;
}

typedef ToolStateRunningData = {
	final status:String;
	final input:ToolCallInput;
	@:optional final title:String;
	@:optional final metadata:ToolStateMetadata;
	final time:{
		final start:Float;
	};
}

typedef ToolStateCompletedData = {
	final status:String;
	final input:ToolCallInput;
	final output:String;
	final title:String;
	final metadata:ToolStateMetadata;
	final time:ToolTimeRange;
	@:optional final attachments:Array<FilePartData>;
}

typedef ToolStateErrorData = {
	final status:String;
	final input:ToolCallInput;
	final error:String;
	@:optional final metadata:ToolStateMetadata;
	final time:ToolTimeRange;
}

enum ToolState {
	ToolPending(data:ToolStatePendingData);
	ToolRunning(data:ToolStateRunningData);
	ToolCompleted(data:ToolStateCompletedData);
	ToolErrored(data:ToolStateErrorData);
}

typedef ToolPartData = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
	final type:String;
	final callID:String;
	final tool:String;
	final state:ToolState;
	@:optional final metadata:ToolStateMetadata;
}

enum Part {
	SnapshotPart(data:SnapshotPartData);
	PatchPart(data:PatchPartData);
	TextPart(data:TextPartData);
	ReasoningPart(data:ReasoningPartData);
	FilePart(data:FilePartData);
	AgentPart(data:AgentPartData);
	CompactionPart(data:CompactionPartData);
	SubtaskPart(data:SubtaskPartData);
	RetryPart(data:RetryPartData);
	StepStartPart(data:StepStartPartData);
	StepFinishPart(data:StepFinishPartData);
	ToolPart(data:ToolPartData);
}

typedef WithParts = {
	final info:Info;
	final parts:Array<Part>;
}

typedef Cursor = {
	final id:MessageID;
	final time:Float;
}
