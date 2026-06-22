package opencodehx.externs.node;

import haxe.extern.EitherType;
import js.html.URL;

@:jsRequire("node:url")
extern class Url {
	static function fileURLToPath(url:EitherType<String, URL>):String;
	static function pathToFileURL(path:String):NodeFileUrl;
}

typedef NodeFileUrl = {
	final href:String;
}
