package opencodehx.lsp;

import genes.ts.Unknown;

typedef LspPosition = {
	final line:Int;
	final character:Int;
}

typedef LspRange = {
	final start:LspPosition;
	final end:LspPosition;
}

typedef LspDiagnosticInfo = {
	final range:LspRange;
	final message:String;
	@:optional final severity:Int;
}

typedef LspLocationInput = {
	final file:String;
	final line:Int;
	final character:Int;
}

typedef LspStatus = {
	final id:String;
	final name:String;
	final root:String;
	final status:String;
}

typedef LspInitializeRequest = {
	final rootUri:String;
	final processId:Int;
	final workspaceFolders:Array<LspWorkspaceFolder>;
}

typedef LspWorkspaceFolder = {
	final name:String;
	final uri:String;
}

typedef LspEndpointResult = {
	final ok:Bool;
	@:optional final value:Unknown;
	@:optional final error:String;
	@:optional final timeout:Bool;
}

typedef LspEndpoint = {
	function setClientRequestHandler(handler:String->Unknown):Void;
	function initialize(request:LspInitializeRequest):LspEndpointResult;
	function sendRequest(method:String, params:Unknown):LspEndpointResult;
	function sendNotification(method:String, params:Unknown):Void;
	function shutdown():Void;
}

typedef LspRuntimeContext = {
	final directory:String;
	final worktree:String;
}

typedef LspServerHandle = {
	final endpoint:LspEndpoint;
	@:optional final processId:Int;
}

typedef LspServerDefinition = {
	final id:String;
	final extensions:Array<String>;
	final root:(String, LspRuntimeContext) -> Null<String>;
	final spawn:(String, LspRuntimeContext) -> Null<LspServerHandle>;
}

typedef LspRuntimeOptions = {
	final directory:String;
	@:optional final worktree:String;
	final enabled:Bool;
	@:optional final servers:Array<LspServerDefinition>;
	@:optional final disabled:Array<String>;
}

class LspInitializeException extends haxe.Exception {}
