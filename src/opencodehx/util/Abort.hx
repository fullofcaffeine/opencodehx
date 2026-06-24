package opencodehx.util;

import js.html.AbortSignal;
import opencodehx.externs.web.AbortControllerWithReason;
import opencodehx.externs.web.AbortControllerWithReason.AbortSignalRuntime;
import opencodehx.externs.web.WebStreams.WebTimerHandle;
import opencodehx.externs.web.WebStreams.WebTimers;

typedef AbortAfterResult = {
	final controller:AbortControllerWithReason;
	final signal:AbortSignal;
	final clearTimeout:Void->Void;
}

typedef AbortAfterAnyResult = {
	final signal:AbortSignal;
	final clearTimeout:Void->Void;
}

class Abort {
	public static function abortAfter(ms:Int):AbortAfterResult {
		final controller = new AbortControllerWithReason();
		final timer:WebTimerHandle = WebTimers.setTimeout(controller.abortNow, ms);
		return {
			controller: controller,
			signal: controller.signal,
			clearTimeout: () -> WebTimers.clearTimeout(timer),
		};
	}

	public static function abortAfterAny(ms:Int, signals:Array<AbortSignal>):AbortAfterAnyResult {
		final timeout = abortAfter(ms);
		return {
			signal: AbortSignalRuntime.any([timeout.signal].concat(signals)),
			clearTimeout: timeout.clearTimeout,
		};
	}
}
