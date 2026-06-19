package opencodehx.tui;

import genes.js.Async.await;
import genes.react.Element;
import genes.react.JSX.*;
import js.Syntax;
import js.lib.Promise;
import opencodehx.externs.opentui.OpenTuiSolid;

@:jsx_inline_markup
class TuiScaffold {
	static function main():Void {
		run().then(_ -> {
			Syntax.code("console.log({0})", "tui-scaffold:ok");
			return null;
		});
	}

	@:async
	static function run():Promise<Void> {
		final rendered = await(OpenTuiSolid.testRender(renderView, {width: 40, height: 8}));
		await(rendered.renderOnce());
		final first = rendered.captureCharFrame();
		contains(first, "OpenCodeHX TUI", "static title");
		await(rendered.mockInput.typeText("x"));
		await(rendered.renderOnce());
		final second = rendered.captureCharFrame();
		contains(second, "x", "typed input");
		rendered.mockInput.pressCtrlC();
	}

	static function renderView():Element {
		return jsx('<box flexDirection="column"><text>OpenCodeHX TUI</text><input focused={true} value={""} /></box>');
	}

	static function contains(frame:String, expected:String, label:String):Void {
		if (frame.indexOf(expected) == -1)
			throw '${label}: expected frame to contain "${expected}", got:\n${frame}';
	}
}
