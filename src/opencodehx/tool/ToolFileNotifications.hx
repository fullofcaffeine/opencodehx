package opencodehx.tool;

import opencodehx.file.FileToolEvents;
import opencodehx.file.FileToolEvents.FileWatcherUpdateKind;
import opencodehx.tool.ToolTypes.ToolContext;

class ToolFileNotifications {
	public static function edited(ctx:ToolContext, file:String):Void {
		final bus = ctx.bus;
		if (bus != null)
			bus.publish(FileToolEvents.Edited, {file: file});
	}

	public static function watcherUpdated(ctx:ToolContext, file:String, event:FileWatcherUpdateKind):Void {
		final bus = ctx.bus;
		if (bus != null)
			bus.publish(FileToolEvents.WatcherUpdated, {file: file, event: event});
	}
}
