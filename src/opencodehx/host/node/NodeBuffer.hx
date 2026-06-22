package opencodehx.host.node;

import js.lib.Uint8Array;
import opencodehx.externs.node.Buffer;
import opencodehx.externs.node.Buffer.NodeBufferData;

class NodeBuffer {
	public static function fromBase64(value:String):String {
		final buffer = Buffer.from(value, "base64");
		return buffer.toString("utf8");
	}

	public static function toBase64Url(value:String):String {
		final buffer = Buffer.from(value, "utf8");
		return buffer.toString("base64url");
	}

	public static function fromBase64Url(value:String):String {
		final buffer = Buffer.from(value, "base64url");
		return buffer.toString("utf8");
	}

	public static function fromBytesBase64(value:Uint8Array):String {
		final buffer = Buffer.from(value);
		return buffer.toString("base64");
	}

	public static function fromBytesUtf8(value:Uint8Array):String {
		final buffer = Buffer.from(value);
		return buffer.toString("utf8");
	}

	public static function byteLength(value:NodeBufferData):Int {
		return value.byteLength;
	}

	public static function prefixBytes(value:NodeBufferData, count:Int):Array<Int> {
		final safeCount = count < 0 ? 0 : count;
		final view = value.subarray(0, safeCount);
		final out:Array<Int> = [];
		for (index in 0...view.length)
			out.push(view[index]);
		return out;
	}
}
