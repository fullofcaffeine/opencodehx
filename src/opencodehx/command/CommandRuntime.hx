package opencodehx.command;

import opencodehx.bus.EventBus;

enum abstract CommandEventType(String) to String {
	var Executed = "command.executed";
}

enum abstract CommandDefaultName(String) to String {
	var Init = "init";
	var Review = "review";
}

typedef CommandExecutedEvent = {
	final type:CommandEventType;
	final name:String;
	final sessionID:String;
	final arguments:String;
	final messageID:String;
}

class CommandRuntime {
	final bus:EventBus<CommandExecutedEvent>;

	public function new(?bus:EventBus<CommandExecutedEvent>) {
		this.bus = bus == null ? new EventBus<CommandExecutedEvent>() : bus;
	}

	public function events():Array<CommandExecutedEvent> {
		return bus.snapshot();
	}

	public function subscribe(listener:CommandExecutedEvent->Void):Void->Void {
		return bus.subscribe(listener);
	}

	public function executed(input:{
		final name:String;
		final sessionID:String;
		final arguments:String;
		final messageID:String;
	}):Void {
		bus.publish({
			type: Executed,
			name: input.name,
			sessionID: input.sessionID,
			arguments: input.arguments,
			messageID: input.messageID,
		});
	}
}
