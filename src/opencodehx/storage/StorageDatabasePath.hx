package opencodehx.storage;

import haxe.DynamicAccess;
import opencodehx.host.node.GlobalPaths;
import opencodehx.host.node.NodePath;

class StorageDatabasePath {
	public static function getChannelPath(env:DynamicAccess<String>, channel:String, ?disableChannelDb:Bool):String {
		if (disableChannelDb == true || channel == "latest" || channel == "beta" || channel == "prod")
			return NodePath.join(GlobalPaths.data(env), "opencode.db");
		return NodePath.join(GlobalPaths.data(env), 'opencode-${sanitizeChannel(channel)}.db');
	}

	public static function path(env:DynamicAccess<String>, channel:String, ?disableChannelDb:Bool):String {
		final configured = env.get("OPENCODE_DB");
		if (configured != null && configured != "") {
			if (configured == ":memory:" || NodePath.isAbsolute(configured))
				return configured;
			return NodePath.join(GlobalPaths.data(env), configured);
		}
		return getChannelPath(env, channel, disableChannelDb);
	}

	static function sanitizeChannel(channel:String):String {
		final out = new StringBuf();
		for (index in 0...channel.length) {
			final code = channel.charCodeAt(index);
			if (code == null)
				continue;
			final valid = (code >= "A".code && code <= "Z".code)
				|| (code >= "a".code && code <= "z".code)
				|| (code >= "0".code && code <= "9".code)
				|| code == ".".code
				|| code == "_".code
				|| code == "-".code;
			out.addChar(valid ? code : "-".code);
		}
		return out.toString();
	}
}
