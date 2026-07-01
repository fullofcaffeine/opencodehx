package opencodehx.smoke;

import genes.js.Async.await;
import js.lib.Promise;

/**
	Shared cleanup helpers for smoke fixtures that allocate temporary host state.
	They intentionally contain the smoke-runner catch boundary so individual
	fixtures can keep their assertions typed and avoid repeated broad catches.
**/
function withCleanup(work:Void->Void, cleanup:Void->Void):Void {
	cleanupAround(work, cleanup, true);
}

function withFailureCleanup(work:Void->Void, cleanup:Void->Void):Void {
	cleanupAround(work, cleanup, false);
}

@:async
function withCleanupAsync(work:Void->Promise<Void>, cleanup:Void->Void):Promise<Void> {
	try {
		await(work());
		// This broad smoke harness catch is required because async host
		// externs, assertions, Haxe exceptions, and native JS errors can all
		// escape through the shared runner. Cleanup/rethrow behavior is
		// centralized here so fixture code does not spread weak exception types.
	} catch (error:Dynamic) {
		cleanup();
		throw error;
	}
	cleanup();
}

private function cleanupAround(work:Void->Void, cleanup:Void->Void, always:Bool):Void {
	try {
		work();
		// This broad smoke harness catch is required because host externs,
		// assertions, Haxe exceptions, and native JS errors can all escape
		// through the shared runner. Cleanup/rethrow behavior is centralized
		// here so fixture code does not spread weak exception types.
	} catch (error:Dynamic) {
		cleanup();
		throw error;
	}
	if (always)
		cleanup();
}
