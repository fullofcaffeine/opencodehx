package opencodehx.effect;

import opencodehx.project.InstanceRuntime;
import opencodehx.project.InstanceRuntime.InstanceContext;

class InstanceStateRuntime<T> {
	final factory:InstanceContext->T;
	final disposeValue:Null<T->Void>;
	final values:Map<String, T> = new Map();
	var unsubscribe:Null<Void->Void> = null;

	public function new(factory:InstanceContext->T, ?disposeValue:T->Void) {
		this.factory = factory;
		this.disposeValue = disposeValue;
		unsubscribe = InstanceRuntime.subscribe(event -> invalidate(event.directory));
	}

	public function get(context:InstanceContext):T {
		final existing = values.get(context.directory);
		if (existing != null)
			return existing;
		final value = factory(context);
		values.set(context.directory, value);
		return value;
	}

	public function invalidate(directory:String):Void {
		final existing = values.get(directory);
		if (existing == null)
			return;
		values.remove(directory);
		if (disposeValue != null)
			disposeValue(existing);
	}

	public function dispose():Void {
		final directories:Array<String> = [];
		for (directory in values.keys())
			directories.push(directory);
		for (directory in directories)
			invalidate(directory);
		if (unsubscribe != null) {
			unsubscribe();
			unsubscribe = null;
		}
	}
}
