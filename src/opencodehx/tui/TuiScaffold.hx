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
	static final transcriptRows = TuiSessionTranscript.rows(TuiSessionTranscript.fakeProviderToolFixture());

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
		assertEquals(4, transcriptRows.length, "transcript row count");
		assertEquals("User", transcriptRows[0].label, "user transcript label");
		assertEquals("Tool", transcriptRows[1].label, "tool transcript label");
		assertEquals("Assistant", transcriptRows[2].label, "assistant transcript label");

		final rendered = await(OpenTuiSolid.testRender(renderView, {width: 64, height: 12}));
		await(rendered.renderOnce());
		final first = rendered.captureCharFrame();
		contains(first, "OpenCodeHX TUI", "static title");
		contains(first, "Theme List", "plugin route label");
		contains(first, "ctrl+x t", "keybind metadata");
		contains(first, "User: Say hello from the fixture.", "user transcript row");
		contains(first, "Tool: fixture_lookup: Fixture lookup completed", "tool transcript row");
		contains(first, "Assistant: Hello from the fake provider.", "assistant transcript row");
		contains(first, "Meta: Primary - Test Model", "assistant metadata row");
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
		final user = transcriptRows[0];
		final tool = transcriptRows[1];
		final assistant = transcriptRows[2];
		final meta = transcriptRows[3];
		return <box flexDirection="column">
			<text fg={theme.primary}>OpenCodeHX TUI</text>
			<text>{"Route: " + routeLabel}</text>
			<text>{"Theme: " + foundation.theme.selected() + " " + foundation.theme.mode()}</text>
			<text>{"Key: " + key}</text>
			<text>{user.label + ": " + user.text}</text>
			<text>{tool.label + ": " + tool.text}</text>
			<text>{assistant.label + ": " + assistant.text}</text>
			<text>{meta.label + ": " + meta.text}</text>
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
