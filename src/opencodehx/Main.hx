package opencodehx;

import js.Syntax;

class Main {
	static function main():Void {
		Syntax.code("console.log({0})", BuildInfo.label());
	}
}
