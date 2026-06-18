package opencodehx.externs.node;

@:jsRequire("node:url")
extern class Url {
	static function fileURLToPath(url:Dynamic):String;
}
