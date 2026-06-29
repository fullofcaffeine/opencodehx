package opencodehx.tool;

import opencodehx.file.FileSystem;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolTypes.ToolContext;

class ToolPaths {
	public static function resolveAny(ctx:ToolContext, value:String):String {
		final root = ctx.directory;
		return NodePath.isAbsolute(value) ? NodePath.resolve(value, ".") : NodePath.resolve(root, value);
	}

	public static function resolve(ctx:ToolContext, value:String):String {
		final absolute = resolveAny(ctx, value);
		if (!FileSystem.contains(ctx.directory, absolute))
			throw "Access denied: path escapes project directory";
		return absolute;
	}

	public static function relative(ctx:ToolContext, absolute:String):String {
		var root = ctx.directory;
		if (ctx.worktree != null)
			root = ctx.worktree;
		return normalize(NodePath.relative(root, absolute));
	}

	public static function normalize(path:String):String {
		return StringTools.replace(path, "\\", "/");
	}
}
