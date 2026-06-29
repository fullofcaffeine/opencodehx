package opencodehx.tool;

/**
	Shared UTF-8 BOM handling for text tools.

	OpenCode treats a leading BOM as file encoding metadata, not editable text:
	tools strip it before matching and diffing, then restore it when the source
	or replacement content carried one.
**/
typedef BomText = {
	final bom:Bool;
	final text:String;
}

private inline function bomCode():Int {
	return 0xfeff;
}

function split(text:String):BomText {
	if (text.length == 0 || text.charCodeAt(0) != bomCode())
		return {bom: false, text: text};
	return {bom: true, text: text.substr(1)};
}

function join(text:String, bom:Bool):String {
	final stripped = split(text).text;
	return bom ? String.fromCharCode(bomCode()) + stripped : stripped;
}
