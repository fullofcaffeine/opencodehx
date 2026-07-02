package opencodehx.file;

import opencodehx.bus.BusRuntime;
import opencodehx.bus.BusRuntime.BusEventDefinition;

typedef FileEditedPayload = {
	final file:String;
}

enum abstract FileWatcherUpdateKind(String) to String {
	var Add = "add";
	var Change = "change";
	var Unlink = "unlink";
}

typedef FileWatcherUpdatedPayload = {
	final file:String;
	final event:FileWatcherUpdateKind;
}

class FileToolEvents {
	public static final Edited:BusEventDefinition<FileEditedPayload> = BusRuntime.define("file.edited");
	public static final WatcherUpdated:BusEventDefinition<FileWatcherUpdatedPayload> = BusRuntime.define("file.watcher.updated");
}
