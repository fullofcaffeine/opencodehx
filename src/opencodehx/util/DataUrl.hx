package opencodehx.util;

import opencodehx.externs.web.UriCodec;
import opencodehx.host.node.NodeBuffer;

class DataUrl {
	public static function decode(url:String):String {
		final idx = url.indexOf(",");
		if (idx == -1)
			return "";

		final head = url.substr(0, idx);
		final body = url.substr(idx + 1);
		if (head.indexOf(";base64") != -1)
			return NodeBuffer.fromBase64(body);
		return UriCodec.decodeComponent(body);
	}
}
