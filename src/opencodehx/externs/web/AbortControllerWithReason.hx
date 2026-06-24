package opencodehx.externs.web;

import js.html.AbortSignal;

/**
 * Narrow global AbortController surface with the modern abort reason parameter.
 *
 * Haxe's DOM extern does not expose `abort(reason)`, while the AI SDK path
 * intentionally aborts with a reason string. Keep that host API shape here
 * instead of using raw `js.Syntax.code` at the provider call site.
 */
@:native("AbortController")
extern class AbortControllerWithReason {
	public final signal:AbortSignal;

	function new();
	@:native("abort")
	function abortNow():Void;
	function abort(?reason:String):Void;
}

@:native("AbortSignal")
extern class AbortSignalRuntime {
	static function any(signals:Array<AbortSignal>):AbortSignal;
}
