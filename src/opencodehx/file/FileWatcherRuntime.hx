package opencodehx.file;

enum abstract FileWatchEventType(String) to String {
	var FileUpdated = "file.updated";
}

typedef FileUpdatedEvent = {
	final type:FileWatchEventType;
	final directory:Null<String>;
	final file:String;
}
