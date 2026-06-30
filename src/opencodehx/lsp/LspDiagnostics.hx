package opencodehx.lsp;

import opencodehx.lsp.LspTypes.LspDiagnosticInfo;

/**
 * URI-keyed diagnostic store owned by the LSP runtime.
 *
 * Diagnostics are not arbitrary JSON; they are typed records grouped by source
 * URI. Keep the string key at this runtime boundary, but expose only copied
 * arrays so client/runtime aggregation cannot mutate another owner's state.
 */
class LspDiagnostics {
	final byUri:Map<String, Array<LspDiagnosticInfo>> = [];

	public function new() {}

	public function keys():Array<String> {
		final out:Array<String> = [];
		for (key in byUri.keys())
			out.push(key);
		return out;
	}

	public function hasAny():Bool {
		for (_ in byUri.keys())
			return true;
		return false;
	}

	public function get(uri:String):Array<LspDiagnosticInfo> {
		final hit = byUri.get(uri);
		return hit == null ? [] : hit.copy();
	}

	public function set(uri:String, diagnostics:Array<LspDiagnosticInfo>):Void {
		byUri.set(uri, diagnostics.copy());
	}

	public function appendAll(uri:String, diagnostics:Array<LspDiagnosticInfo>):Void {
		if (diagnostics.length == 0)
			return;
		final next = get(uri);
		for (item in diagnostics)
			next.push(item);
		byUri.set(uri, next);
	}

	public function mergeFrom(other:LspDiagnostics):Void {
		for (key in other.keys())
			appendAll(key, other.get(key));
	}
}
