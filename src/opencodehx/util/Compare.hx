package opencodehx.util;

/**
	Typed comparator helpers for deterministic sorting without runtime reflection.
**/
function compareString(left:String, right:String):Int {
	return left < right ? -1 : (left > right ? 1 : 0);
}

function compareInt(left:Int, right:Int):Int {
	return left < right ? -1 : (left > right ? 1 : 0);
}

function compareFloat(left:Float, right:Float):Int {
	return left < right ? -1 : (left > right ? 1 : 0);
}
