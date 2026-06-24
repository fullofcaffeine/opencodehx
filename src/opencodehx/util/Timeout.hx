package opencodehx.util;

import js.lib.Error;
import js.lib.Promise;
import opencodehx.externs.web.WebStreams.WebTimerHandle;
import opencodehx.externs.web.WebStreams.WebTimers;

class Timeout {
	public static function withTimeout<T>(promise:Promise<T>, ms:Int):Promise<T> {
		var timeout:Null<WebTimerHandle> = null;
		return new Promise<T>((resolve, reject) -> {
			timeout = WebTimers.setTimeout(() -> {
				reject(new Error('Operation timed out after ${ms}ms'));
			}, ms);
			promise.then(result -> {
				if (timeout != null)
					WebTimers.clearTimeout(timeout);
				resolve(result);
				return null;
			}).catchError(error -> {
				reject(error);
				return null;
			});
		});
	}
}
