package opencodehx.externs.toml;

@:jsRequire("toml")
extern class Toml {
	static function parse(text:String):TomlObject;
}
