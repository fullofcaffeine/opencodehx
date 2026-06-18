package opencodehx.tool;

typedef ToolContext = {
	final directory:String;
	@:optional final worktree:String;
	@:optional final sessionID:String;
	@:optional final messageID:String;
	@:optional final agent:String;
	@:optional final callID:String;
	@:optional final ask:(ToolPermissionRequest) -> ToolPermissionDecision;
}

typedef ToolPermissionRequest = {
	final permission:String;
	final patterns:Array<String>;
	final always:Array<String>;
	final metadata:Dynamic;
}

typedef ToolPermissionDecision = {
	final allowed:Bool;
	@:optional final reason:String;
}

typedef ToolResult = {
	final title:String;
	final output:String;
	final metadata:Dynamic;
	@:optional final attachments:Array<Dynamic>;
}

typedef ToolParameter = {
	final name:String;
	final type:String;
	final required:Bool;
	@:optional final description:String;
}

typedef ToolSchema = {
	final parameters:Array<ToolParameter>;
}

typedef ToolDef = {
	final id:String;
	final description:String;
	final schema:ToolSchema;
	final execute:(Dynamic, ToolContext) -> ToolResult;
}
