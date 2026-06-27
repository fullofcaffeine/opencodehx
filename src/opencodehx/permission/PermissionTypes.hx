package opencodehx.permission;

import opencodehx.tool.ToolTypes.ToolPermissionRequest;
import opencodehx.tool.ToolTypes.ToolPermissionMetadata;

typedef PermissionRule = {
	final permission:String;
	final pattern:String;
	final action:String;
}

typedef PermissionAskRecord = {
	final id:String;
	final sessionID:String;
	final permission:String;
	final patterns:Array<String>;
	final metadata:ToolPermissionMetadata;
	final always:Array<String>;
	@:optional final tool:{
		final messageID:String;
		final callID:String;
	};
}

typedef PermissionReply = {
	final reply:String;
	@:optional final message:String;
}

typedef PermissionRuntimeOptions = {
	final ruleset:Array<PermissionRule>;
	@:optional final approved:Array<PermissionRule>;
	@:optional final sessionID:String;
	@:optional final messageID:String;
	@:optional final callID:String;
	@:optional final prompt:(PermissionAskRecord) -> PermissionReply;
}

typedef PermissionRuntimeDecision = {
	final allowed:Bool;
	final action:String;
	@:optional final reason:String;
	@:optional final request:PermissionAskRecord;
}

typedef ToolPermissionAdapter = ToolPermissionRequest->opencodehx.tool.ToolTypes.ToolPermissionDecision;
