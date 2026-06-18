package opencodehx.tool;

typedef ToolContext = {
	final directory:String;
	@:optional final worktree:String;
	@:optional final sessionID:String;
	@:optional final messageID:String;
	@:optional final agent:String;
	@:optional final callID:String;
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
