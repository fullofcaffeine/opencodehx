package opencodehx.tui;

import genes.js.Async.await;
import genes.react.Element;
import js.lib.Promise;
import opencodehx.externs.node.Console;
import opencodehx.externs.opentui.OpenTuiSolid;
import opencodehx.tui.TuiDialogReplay.TuiDialogAction;
import opencodehx.tui.TuiFoundation.TuiDispatchResult;
import opencodehx.tui.TuiKeybind.TuiKeybindActions;
import opencodehx.tui.TuiKeybind.TuiParsedKey;

class TuiScaffold {
	static final foundation = TuiFoundation.demo();
	static final transcriptRows = TuiSessionTranscript.rows(TuiSessionTranscript.fakeProviderToolFixture());
	static final dialogRows = TuiDialogReplay.fixtureRows();

	static function main():Void {
		run().then(_ -> {
			Console.log("tui-scaffold:ok");
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
		assertEquals(21, dialogRows.length, "dialog row count");
		assertEquals("Dialog", dialogRows[0].label, "model dialog label");
		assertEquals("Select model", dialogRows[0].text, "model dialog title");
		assertAction("model openai/gpt-5.2", TuiDialogReplay.selectModel(TuiDialogReplay.modelFixture(), 0), "model selection");
		assertAction("provider openai -> api", TuiDialogReplay.selectProvider(TuiDialogReplay.providerFixture(), 1), "provider selection");
		assertAction("session ses_today", TuiDialogReplay.selectSession(TuiDialogReplay.sessionFixture(), 0), "session selection");
		assertAction("permission once", TuiDialogReplay.replyPermission(TuiDialogReplay.permissionFixture(), Once), "permission allow once");
		assertAction("permission reject: Use a smaller edit",
			TuiDialogReplay.replyPermission(TuiDialogReplay.permissionFixture(), Reject, "Use a smaller edit"), "permission rejection");

		final rendered = await(OpenTuiSolid.testRender(renderView, {width: 76, height: 30}));
		await(rendered.renderOnce());
		final first = rendered.captureCharFrame();
		contains(first, "OpenCodeHX TUI", "static title");
		contains(first, "Theme List", "plugin route label");
		contains(first, "ctrl+x t", "keybind metadata");
		contains(first, "User: Say hello from the fixture.", "user transcript row");
		contains(first, "Tool: fixture_lookup: Fixture lookup completed", "tool transcript row");
		contains(first, "Assistant: Hello from the fake provider.", "assistant transcript row");
		contains(first, "Meta: Primary - Test Model", "assistant metadata row");
		contains(first, "Dialog: Select model", "model dialog title");
		contains(first, "Option: Recent: GPT-5.2 - OpenAI", "model option");
		contains(first, "Dialog: Connect a provider", "provider dialog title");
		contains(first, "Option: Popular: OpenAI", "provider option");
		contains(first, "Dialog: Sessions", "session dialog title");
		contains(first, "Option: Today: Refactor compiler seam", "session option");
		contains(first, "Dialog: Permission required", "permission dialog title");
		contains(first, "Request: Edit src/opencodehx/Main.hx", "permission request");
		contains(first, "Action: permission reject: Use a smaller edit", "permission reject action");
		await(rendered.mockInput.typeText("x"));
		await(rendered.renderOnce());
		final second = rendered.captureCharFrame();
		contains(second, "x", "typed input");
		rendered.mockInput.pressCtrlC();
	}

	static function renderView():Element {
		final routeLabel = foundation.route.currentLabel();
		final theme = foundation.theme.current();
		final key = foundation.keybind.print(TuiKeybindActions.action("theme_list"));
		final user = transcriptRows[0];
		final tool = transcriptRows[1];
		final assistant = transcriptRows[2];
		final meta = transcriptRows[3];
		final modelTitle = dialogRows[0];
		final modelOption = dialogRows[1];
		final providerTitle = dialogRows[3];
		final providerOption = dialogRows[5];
		final sessionTitle = dialogRows[7];
		final sessionOption = dialogRows[8];
		final permissionTitle = dialogRows[10];
		final permissionRequest = dialogRows[11];
		final permissionChoices = dialogRows[13];
		final modelAction = dialogRows[16];
		final providerAction = dialogRows[17];
		final sessionAction = dialogRows[18];
		final permissionAllowAction = dialogRows[19];
		final permissionRejectAction = dialogRows[20];
		return <box flexDirection="column">
			<text fg={theme.primary}>OpenCodeHX TUI</text>
			<text>{"Route: " + routeLabel}</text>
			<text>{"Theme: " + foundation.theme.selected() + " " + foundation.theme.mode()}</text>
			<text>{"Key: " + key}</text>
			<text>{user.label + ": " + user.text}</text>
			<text>{tool.label + ": " + tool.text}</text>
			<text>{assistant.label + ": " + assistant.text}</text>
			<text>{meta.label + ": " + meta.text}</text>
			<text>{modelTitle.label + ": " + modelTitle.text}</text>
			<text>{modelOption.label + ": " + modelOption.text}</text>
			<text>{providerTitle.label + ": " + providerTitle.text}</text>
			<text>{providerOption.label + ": " + providerOption.text}</text>
			<text>{sessionTitle.label + ": " + sessionTitle.text}</text>
			<text>{sessionOption.label + ": " + sessionOption.text}</text>
			<text>{permissionTitle.label + ": " + permissionTitle.text}</text>
			<text>{permissionRequest.label + ": " + permissionRequest.text}</text>
			<text>{permissionChoices.label + ": " + permissionChoices.text}</text>
			<text>{modelAction.label + ": " + modelAction.text}</text>
			<text>{providerAction.label + ": " + providerAction.text}</text>
			<text>{sessionAction.label + ": " + sessionAction.text}</text>
			<text>{permissionAllowAction.label + ": " + permissionAllowAction.text}</text>
			<text>{permissionRejectAction.label + ": " + permissionRejectAction.text}</text>
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

	static function assertAction(expected:String, actual:TuiDialogAction, label:String):Void {
		assertEquals(expected, TuiDialogReplay.actionText(actual), label);
	}
}
