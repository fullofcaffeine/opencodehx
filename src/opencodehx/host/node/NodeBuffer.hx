package opencodehx.host.node;

import js.Syntax;
import js.lib.Uint8Array;
import opencodehx.externs.node.Buffer;
import opencodehx.externs.node.Buffer.NodeBufferData;

class NodeBuffer {
	public static function fromBase64(value:String):String {
		final buffer = Buffer.from(value, "base64");
		// Buffer.toString is the Node host boundary for base64 helpers.
		return Syntax.code("{0}.toString('utf8')", buffer);
	}

	public static function toBase64Url(value:String):String {
		final buffer = Buffer.from(value, "utf8");
		// Keep the Node-only base64url encoding string inside the host facade.
		return Syntax.code("{0}.toString('base64url')", buffer);
	}

	public static function fromBase64Url(value:String):String {
		final buffer = Buffer.from(value, "base64url");
		return Syntax.code("{0}.toString('utf8')", buffer);
	}

	public static function fromBytesBase64(value:Uint8Array):String {
		final buffer = Buffer.from(value);
		return Syntax.code("{0}.toString('base64')", buffer);
	}

	public static function byteLength(value:NodeBufferData):Int {
		// Node Buffer is an opaque host value in Haxe. Keep property reads here
		// rather than leaking raw byte operations into resource/app modules.
		return Syntax.code("{0}.byteLength", value);
	}

	public static function prefixBytes(value:NodeBufferData, count:Int):Array<Int> {
		final safeCount = count < 0 ? 0 : count;
		// Node exposes Buffer slicing and byte iteration, but those APIs do not
		// have a portable Haxe representation. The result is immediately narrowed
		// to Array<Int> for app-facing resource checks.
		return Syntax.code("Array.from({0}.subarray(0, {1}))", value, safeCount);
	}
}
