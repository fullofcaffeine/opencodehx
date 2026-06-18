package opencodehx;

import js.Syntax;
import opencodehx.host.node.NodePath;

class Main {
	static function main():Void {
		final smokePath = NodePath.normalize(NodePath.join("opencodehx", "smoke"));
		Syntax.code("console.log({0})", '${BuildInfo.label()} ${smokePath}');
	}
}
