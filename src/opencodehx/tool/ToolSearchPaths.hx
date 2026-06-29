package opencodehx.tool;

import opencodehx.host.node.NodePath;

/**
	Decoded search root for tools that default to the active workspace but accept
	a caller-supplied file or directory path.
**/
enum ToolSearchPath {
	DefaultSearchPath;
	RequestedSearchPath(path:String);
}

function fromNullable(value:Null<String>):ToolSearchPath {
	return value == null ? DefaultSearchPath : RequestedSearchPath(value);
}

function toNullable(path:ToolSearchPath):Null<String> {
	return switch path {
		case DefaultSearchPath: null;
		case RequestedSearchPath(value): value;
	}
}

function resolve(root:String, path:ToolSearchPath):String {
	return switch path {
		case DefaultSearchPath:
			root;
		case RequestedSearchPath(value):
			NodePath.isAbsolute(value) ? NodePath.resolve(value, ".") : NodePath.resolve(root, value);
	}
}
