package opencodehx.externs.treesitter;

import js.Syntax;
import js.lib.Promise;

typedef ParserInitOptions = {
	final locateFile:String->String;
}

@:jsRequire("web-tree-sitter", "Parser")
extern class Parser {
	static function init(?options:ParserInitOptions):Promise<Void>;
	function new();
	function setLanguage(language:Language):Parser;
	function parse(source:String):Null<TreeSitterTree>;
}

@:jsRequire("web-tree-sitter", "Language")
extern class Language {
	static function load(path:String):Promise<Language>;
}

/**
 * Tree-sitter's type-only `Tree` export is not a runtime value. The abstract
 * keeps the raw JS object contained at this extern boundary while exposing the
 * precise fields the scanner needs.
 */
@:ts.type("import('web-tree-sitter').Tree")
abstract TreeSitterTree(Dynamic) from Dynamic {
	public var rootNode(get, never):TreeSitterNode;

	inline function get_rootNode():TreeSitterNode {
		return Syntax.code("{0}.rootNode", this);
	}
}

/**
 * Tree-sitter's node class is also type-only for our generated declarations.
 * Dynamic is justified here as a narrow extern wrapper around parser-owned
 * objects; application code only sees typed scanner results.
 */
@:ts.type("import('web-tree-sitter').Node")
abstract TreeSitterNode(Dynamic) from Dynamic {
	public var type(get, never):String;
	public var text(get, never):String;
	public var childCount(get, never):Int;
	public var parent(get, never):Null<TreeSitterNode>;

	inline function get_type():String {
		return Syntax.code("{0}.type", this);
	}

	inline function get_text():String {
		return Syntax.code("{0}.text", this);
	}

	inline function get_childCount():Int {
		return Syntax.code("{0}.childCount", this);
	}

	inline function get_parent():Null<TreeSitterNode> {
		return Syntax.code("{0}.parent", this);
	}

	public inline function child(index:Int):Null<TreeSitterNode> {
		return Syntax.code("{0}.child({1})", this, index);
	}

	public inline function descendantsOfType(types:String):Array<Null<TreeSitterNode>> {
		return Syntax.code("{0}.descendantsOfType({1})", this, types);
	}
}
