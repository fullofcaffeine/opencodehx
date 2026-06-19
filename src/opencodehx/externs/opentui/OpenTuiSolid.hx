package opencodehx.externs.opentui;

import genes.react.Element;
import js.lib.Promise;

typedef OpenTuiMockInput = {
	function typeText(text:String, ?delayMs:Int):Promise<Void>;
	function pressCtrlC():Void;
}

typedef OpenTuiTestRender = {
	final mockInput:OpenTuiMockInput;
	function renderOnce():Promise<Void>;
	function captureCharFrame():String;
}

typedef OpenTuiRenderConfig = {
	final width:Int;
	final height:Int;
}

@:jsRequire("@opentui/solid")
extern class OpenTuiSolid {
	static function testRender(node:Void->Element, ?renderConfig:OpenTuiRenderConfig):Promise<OpenTuiTestRender>;
}
