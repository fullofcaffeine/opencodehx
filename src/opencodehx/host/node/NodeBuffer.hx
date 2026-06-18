package opencodehx.host.node;

import opencodehx.externs.node.Buffer;

class NodeBuffer {
	public static function fromBase64(value:String):String {
		return Buffer.from(value, "base64").toString("utf8");
	}

	public static function toBase64Url(value:String):String {
		return Buffer.from(value, "utf8").toString("base64url");
	}

	public static function fromBase64Url(value:String):String {
		return Buffer.from(value, "base64url").toString("utf8");
	}
}
