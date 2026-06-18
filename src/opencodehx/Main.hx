package opencodehx;

import js.Syntax;
import opencodehx.fx.Task;
import opencodehx.host.node.NodePath;

class Main {
	static function main():Void {
		final smokePath = NodePath.normalize(NodePath.join("opencodehx", "smoke"));
		final smokeTask = Task.succeed(smokePath);
		Syntax.code("void {0}", smokeTask.toEffect());
		Syntax.code("console.log({0})", '${BuildInfo.label()} ${smokePath}');
	}
}
