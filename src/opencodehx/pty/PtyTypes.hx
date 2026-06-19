package opencodehx.pty;

import haxe.DynamicAccess;

abstract PtyID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):PtyID {
		return new PtyID(value);
	}

	public inline function toString():String {
		return this;
	}
}

enum abstract PtyStatus(String) to String {
	var Running = "running";
	var Exited = "exited";
}

enum abstract PtyEventType(String) to String {
	var Created = "pty.created";
	var Updated = "pty.updated";
	var Exited = "pty.exited";
	var Deleted = "pty.deleted";
}

typedef PtySize = {
	final cols:Int;
	final rows:Int;
}

typedef PtyInfo = {
	final id:PtyID;
	var title:String;
	final command:String;
	final args:Array<String>;
	final cwd:String;
	var status:PtyStatus;
	final pid:Int;
}

typedef PtyCreateInput = {
	@:optional final command:String;
	@:optional final args:Array<String>;
	@:optional final cwd:String;
	@:optional final title:String;
	@:optional final env:DynamicAccess<String>;
}

typedef PtyUpdateInput = {
	@:optional final title:String;
	@:optional final size:PtySize;
}

typedef PtyEvent = {
	final type:PtyEventType;
	final id:PtyID;
	@:optional final info:PtyInfo;
	@:optional final exitCode:Int;
}
