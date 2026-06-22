package opencodehx.externs.treesitter;

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
 * Tree-sitter's `Tree` is a TypeScript-only shape in our source: the runtime
 * value comes from `Parser.parse`, while declarations should retain the
 * upstream `web-tree-sitter` type.
 */
@:ts.type("import('web-tree-sitter').Tree")
extern class TreeSitterTree {
	public final rootNode:TreeSitterNode;
}

/**
 * Narrow extern for the parser-owned node objects the bash scanner reads.
 * Modeling this as an extern class lets Haxe source use normal field/method
 * access while generated TS preserves `import('web-tree-sitter').Node`.
 */
@:ts.type("import('web-tree-sitter').Node")
extern class TreeSitterNode {
	public final type:String;
	public final text:String;
	public final childCount:Int;
	public final parent:Null<TreeSitterNode>;

	public function child(index:Int):Null<TreeSitterNode>;
	public function descendantsOfType(types:String):Array<Null<TreeSitterNode>>;
}
