package opencodehx.host.node;

import opencodehx.externs.node.Buffer;

class NodeBuffer {
	public static function fromBase64(value:String):String {
		return Buffer.from(value, "base64").toString("utf8");
	}
}
