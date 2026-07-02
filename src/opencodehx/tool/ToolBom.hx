package opencodehx.tool;

/**
	Shared UTF-8 BOM handling for text tools.

	OpenCode treats a leading BOM as file encoding metadata, not editable text:
	tools strip it before matching and diffing, then restore it when the source
	or replacement content carried one.

	This is a class, rather than module-level functions, because callers outside
	`opencodehx.tool` need a stable Haxe type path for the shared helper.
**/
typedef BomText = {
	final bom:Bool;
	final text:String;
}

class ToolBom {
	static inline final BOM_CODE = 0xfeff;
	static final BOM = String.fromCharCode(BOM_CODE);

	public static function split(text:String):BomText {
		if (text.length == 0 || text.charCodeAt(0) != BOM_CODE)
			return {bom: false, text: text};
		return {bom: true, text: text.substr(1)};
	}

	public static function join(text:String, bom:Bool):String {
		final stripped = split(text).text;
		return bom ? BOM + stripped : stripped;
	}

	public static function syncFile(read:Void->String, write:String->Void, bom:Bool):String {
		final current = split(read());
		if (current.bom != bom)
			write(join(current.text, bom));
		return current.text;
	}
}
