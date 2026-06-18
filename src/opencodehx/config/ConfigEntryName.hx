package opencodehx.config;

import opencodehx.host.node.NodePath;

class ConfigEntryName {
	public static function fromPath(filePath:String, searchRoots:Array<String>):String {
		final normalized = StringTools.replace(filePath, "\\", "/");
		for (root in searchRoots) {
			final index = normalized.indexOf(root);
			if (index != -1)
				return stripExtension(normalized.substr(index + root.length));
		}
		return stripExtension(NodePath.basename(filePath));
	}

	static function stripExtension(path:String):String {
		final slash = path.lastIndexOf("/");
		final dot = path.lastIndexOf(".");
		return dot > slash ? path.substr(0, dot) : path;
	}
}
