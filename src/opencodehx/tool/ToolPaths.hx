package opencodehx.tool;

import opencodehx.file.FileSystem;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolTypes.ToolContext;

class ToolPaths {
	public static function resolve(ctx:ToolContext, value:String):String {
		final root = ctx.directory;
		final absolute = NodePath.isAbsolute(value) ? NodePath.resolve(value, ".") : NodePath.resolve(root, value);
		if (!FileSystem.contains(root, absolute))
			throw "Access denied: path escapes project directory";
		return absolute;
	}

	public static function relative(ctx:ToolContext, absolute:String):String {
		final root = ctx.worktree == null ? ctx.directory : ctx.worktree;
		return normalize(NodePath.relative(root, absolute));
	}

	public static function normalize(path:String):String {
		return StringTools.replace(path, "\\", "/");
	}
}
