package opencodehx.tui;

import genes.js.Async.await;
import genes.react.Element;
import js.Syntax;
import js.lib.Promise;
import opencodehx.externs.opentui.OpenTuiSolid;
import opencodehx.tui.TuiFoundation.TuiDispatchResult;
import opencodehx.tui.TuiKeybind.TuiParsedKey;

class TuiScaffold {
	static final foundation = TuiFoundation.demo();

	static function main():Void {
		run().then(_ -> {
			Syntax.code("console.log({0})", "tui-scaffold:ok");
			return null;
		});
	}

	@:async
	static function run():Promise<Void> {
		assertEquals("route=home theme=opencode mode=dark primary=#f97316 key=ctrl+x t", foundation.summary(), "initial foundation summary");
		assertEquals(TuiDispatchResult.Leader, foundation.dispatchKey(parsed("x", true)), "leader dispatch");
		assertEquals(true, foundation.leader(), "leader state");
		assertEquals(TuiDispatchResult.ThemeList, foundation.dispatchKey(parsed("t")), "theme key dispatch");
		assertEquals("themes", foundation.route.currentName(), "route after key dispatch");

		final rendered = await(OpenTuiSolid.testRender(renderView, {width: 40, height: 8}));
		await(rendered.renderOnce());
		final first = rendered.captureCharFrame();
		contains(first, "OpenCodeHX TUI", "static title");
		contains(first, "Theme List", "plugin route label");
		contains(first, "ctrl+x t", "keybind metadata");
		await(rendered.mockInput.typeText("x"));
		await(rendered.renderOnce());
		final second = rendered.captureCharFrame();
		contains(second, "x", "typed input");
		rendered.mockInput.pressCtrlC();
	}

	static function renderView():Element {
		final routeLabel = foundation.route.currentLabel();
		final theme = foundation.theme.current();
		final key = foundation.keybind.print("theme_list");
		return <box flexDirection="column">
			<text fg={theme.primary}>OpenCodeHX TUI</text>
			<text>{"Route: " + routeLabel}</text>
			<text>{"Theme: " + foundation.theme.selected() + " " + foundation.theme.mode()}</text>
			<text>{"Key: " + key}</text>
			<input focused={true} value={""} />
		</box>;
	}

	static function contains(frame:String, expected:String, label:String):Void {
		if (frame.indexOf(expected) == -1)
			throw '${label}: expected frame to contain "${expected}", got:\n${frame}';
	}

	static function parsed(name:String, ctrl:Bool = false, meta:Bool = false, shift:Bool = false, superKey:Bool = false):TuiParsedKey {
		return {
			name: name,
			ctrl: ctrl,
			meta: meta,
			shift: shift,
			superKey: superKey,
		};
	}

	static function assertEquals<T>(expected:T, actual:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
