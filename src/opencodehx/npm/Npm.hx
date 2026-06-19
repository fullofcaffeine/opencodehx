package opencodehx.npm;

import opencodehx.host.node.NodeProcess;

class Npm {
	static final WINDOWS_ILLEGAL = ["<", ">", ":", "\"", "|", "?", "*"];

	public static function sanitize(spec:String):String {
		if (NodeProcess.platform() != "win32")
			return spec;
		final out = new StringBuf();
		for (index in 0...spec.length) {
			final char = spec.charAt(index);
			out.add(WINDOWS_ILLEGAL.indexOf(char) == -1 && spec.charCodeAt(index) >= 32 ? char : "_");
		}
		return out.toString();
	}
}
