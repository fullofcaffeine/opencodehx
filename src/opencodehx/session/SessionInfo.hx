package opencodehx.session;

import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.snapshot.SnapshotFileDiff;

typedef SessionSummary = {
	final additions:Int;
	final deletions:Int;
	final files:Int;
	@:optional final diffs:Array<SnapshotFileDiff>;
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
	@:optional final permission:Array<PermissionRule>;
	final time:SessionTime;
}

typedef ProjectInfo = {
	final id:String;
	final worktree:String;
	@:optional final name:String;
}
