package opencodehx.session;

typedef SessionSummary = {
	final additions:Int;
	final deletions:Int;
	final files:Int;
	@:optional final diffs:Array<Dynamic>;
}

typedef SessionShare = {
	final url:String;
}

typedef SessionRevert = {
	final messageID:MessageID;
	@:optional final partID:PartID;
	@:optional final snapshot:String;
	@:optional final diff:String;
}

typedef SessionTime = {
	final created:Float;
	final updated:Float;
	@:optional final compacting:Float;
	@:optional final archived:Float;
}

typedef SessionInfo = {
	final id:SessionID;
	final slug:String;
	final projectID:String;
	@:optional final workspaceID:String;
	final directory:String;
	@:optional final parentID:SessionID;
	final title:String;
	final version:String;
	@:optional final summary:SessionSummary;
	@:optional final share:SessionShare;
	@:optional final revert:SessionRevert;
	@:optional final permission:Dynamic;
	final time:SessionTime;
}

typedef ProjectInfo = {
	final id:String;
	final worktree:String;
	@:optional final name:String;
}
