package opencodehx.project;

import opencodehx.bus.EventBus;
import opencodehx.command.CommandRuntime.CommandDefaultName;
import opencodehx.command.CommandRuntime.CommandEventType;
import opencodehx.command.CommandRuntime.CommandExecutedEvent;
import opencodehx.project.InstanceRuntime.InstanceContext;
import opencodehx.project.InstanceRuntime.InstanceServiceFactory;
import opencodehx.project.InstanceRuntime.InstanceServiceHandle;
import opencodehx.project.InstanceRuntime.InstanceServiceID;

class InstanceBootstrapRuntime {
	public static function upstreamOrder(?commandBus:EventBus<CommandExecutedEvent>, ?overrides:Array<InstanceServiceFactory>):Array<InstanceServiceFactory> {
		final factories:Array<InstanceServiceFactory> = [];
		factories.push(noop(Config));
		factories.push(noop(Plugin));
		factories.push(noop(Lsp));
		factories.push(noop(Share));
		factories.push(noop(Format));
		factories.push(noop(File));
		factories.push(noop(FileWatcher));
		factories.push(noop(Vcs));
		factories.push(noop(Snapshot));
		if (commandBus != null)
			factories.push(commandInitialization(commandBus));
		if (overrides != null) {
			for (factory in overrides)
				factories.push(factory);
		}
		return factories;
	}

	public static function noop(id:InstanceServiceID):InstanceServiceFactory {
		return (_:InstanceContext) -> ({id: id} : InstanceServiceHandle);
	}

	public static function commandInitialization(bus:EventBus<CommandExecutedEvent>):InstanceServiceFactory {
		return (context:InstanceContext) -> {
			final unsubscribe = bus.subscribe(event -> {
				if (event.type == CommandEventType.Executed && event.name == CommandDefaultName.Init)
					ProjectRuntime.setInitialized(context.project.id);
			});
			return {
				id: Command,
				dispose: unsubscribe,
			};
		};
	}
}
