import type {JSX} from "@opentui/solid"
import type {TuiThemeTokens} from "./TuiTheme.js"
import {TuiSessionTranscript} from "./TuiSessionTranscript.js"
import type {TuiTranscriptRow} from "./TuiSessionTranscript.js"
import type {TuiParsedKey} from "./TuiKeybind.js"
import {TuiFoundation} from "./TuiFoundation.js"
import {TuiDialogReplay} from "./TuiDialogReplay.js"
import type {TuiDialogRow, TuiDialogAction} from "./TuiDialogReplay.js"
import type {OpenTuiTestRender} from "../externs/opentui/OpenTuiSolid.js"
import {Exception} from "../../haxe/Exception.js"
import {Register} from "../../genes/Register.js"
import {Std} from "../../Std.js"
import * as OpenTuiSolid from "@opentui/solid"

export class TuiScaffold {
	declare static foundation: TuiFoundation;
	declare static transcriptRows: TuiTranscriptRow[];
	declare static dialogRows: TuiDialogRow[];
	static main(): void {
		TuiScaffold.run().then(function (_: void) {
			console.log("tui-scaffold:ok");
			return null;
		});
	}
	static async run(): Promise<void> {
		TuiScaffold.assertEquals("route=home theme=opencode mode=dark primary=#f97316 key=ctrl+x t", TuiScaffold.foundation.summary(), "initial foundation summary");
		TuiScaffold.assertEquals("leader", TuiScaffold.foundation.dispatchKey(TuiScaffold.parsed("x", true)), "leader dispatch");
		TuiScaffold.assertEquals(true, TuiScaffold.foundation.leader(), "leader state");
		TuiScaffold.assertEquals("theme_list", TuiScaffold.foundation.dispatchKey(TuiScaffold.parsed("t")), "theme key dispatch");
		TuiScaffold.assertEquals("themes", TuiScaffold.foundation.route.currentName(), "route after key dispatch");
		TuiScaffold.assertEquals(4, TuiScaffold.transcriptRows.length, "transcript row count");
		TuiScaffold.assertEquals("User", TuiScaffold.transcriptRows[0].label, "user transcript label");
		TuiScaffold.assertEquals("Tool", TuiScaffold.transcriptRows[1].label, "tool transcript label");
		TuiScaffold.assertEquals("Assistant", TuiScaffold.transcriptRows[2].label, "assistant transcript label");
		TuiScaffold.assertEquals(21, TuiScaffold.dialogRows.length, "dialog row count");
		TuiScaffold.assertEquals("Dialog", TuiScaffold.dialogRows[0].label, "model dialog label");
		TuiScaffold.assertEquals("Select model", TuiScaffold.dialogRows[0].text, "model dialog title");
		TuiScaffold.assertAction("model openai/gpt-5.2", TuiDialogReplay.selectModel(TuiDialogReplay.modelFixture(), 0), "model selection");
		TuiScaffold.assertAction("provider openai -> api", TuiDialogReplay.selectProvider(TuiDialogReplay.providerFixture(), 1), "provider selection");
		TuiScaffold.assertAction("session ses_today", TuiDialogReplay.selectSession(TuiDialogReplay.sessionFixture(), 0), "session selection");
		TuiScaffold.assertAction("permission once", TuiDialogReplay.replyPermission(TuiDialogReplay.permissionFixture(), "once"), "permission allow once");
		TuiScaffold.assertAction("permission reject: Use a smaller edit", TuiDialogReplay.replyPermission(TuiDialogReplay.permissionFixture(), "reject", "Use a smaller edit"), "permission rejection");
		var rendered: OpenTuiTestRender = await OpenTuiSolid.testRender(TuiScaffold.renderView, {"width": 76, "height": 30});
		await rendered.renderOnce();
		var first: string = rendered.captureCharFrame();
		TuiScaffold.contains(first, "OpenCodeHX TUI", "static title");
		TuiScaffold.contains(first, "Theme List", "plugin route label");
		TuiScaffold.contains(first, "ctrl+x t", "keybind metadata");
		TuiScaffold.contains(first, "User: Say hello from the fixture.", "user transcript row");
		TuiScaffold.contains(first, "Tool: fixture_lookup: Fixture lookup completed", "tool transcript row");
		TuiScaffold.contains(first, "Assistant: Hello from the fake provider.", "assistant transcript row");
		TuiScaffold.contains(first, "Meta: Primary - Test Model", "assistant metadata row");
		TuiScaffold.contains(first, "Dialog: Select model", "model dialog title");
		TuiScaffold.contains(first, "Option: Recent: GPT-5.2 - OpenAI", "model option");
		TuiScaffold.contains(first, "Dialog: Connect a provider", "provider dialog title");
		TuiScaffold.contains(first, "Option: Popular: OpenAI", "provider option");
		TuiScaffold.contains(first, "Dialog: Sessions", "session dialog title");
		TuiScaffold.contains(first, "Option: Today: Refactor compiler seam", "session option");
		TuiScaffold.contains(first, "Dialog: Permission required", "permission dialog title");
		TuiScaffold.contains(first, "Request: Edit src/opencodehx/Main.hx", "permission request");
		TuiScaffold.contains(first, "Action: permission reject: Use a smaller edit", "permission reject action");
		await rendered.mockInput.typeText("x");
		await rendered.renderOnce();
		var second: string = rendered.captureCharFrame();
		TuiScaffold.contains(second, "x", "typed input");
		rendered.mockInput.pressCtrlC();
		return;
	}
	static renderView(): JSX.Element {
		var routeLabel: string = TuiScaffold.foundation.route.currentLabel();
		var theme: TuiThemeTokens = TuiScaffold.foundation.theme.current();
		var key: string = TuiScaffold.foundation.keybind.print("theme_list");
		var user: TuiTranscriptRow = TuiScaffold.transcriptRows[0];
		var tool: TuiTranscriptRow = TuiScaffold.transcriptRows[1];
		var assistant: TuiTranscriptRow = TuiScaffold.transcriptRows[2];
		var meta: TuiTranscriptRow = TuiScaffold.transcriptRows[3];
		var modelTitle: TuiDialogRow = TuiScaffold.dialogRows[0];
		var modelOption: TuiDialogRow = TuiScaffold.dialogRows[1];
		var providerTitle: TuiDialogRow = TuiScaffold.dialogRows[3];
		var providerOption: TuiDialogRow = TuiScaffold.dialogRows[5];
		var sessionTitle: TuiDialogRow = TuiScaffold.dialogRows[7];
		var sessionOption: TuiDialogRow = TuiScaffold.dialogRows[8];
		var permissionTitle: TuiDialogRow = TuiScaffold.dialogRows[10];
		var permissionRequest: TuiDialogRow = TuiScaffold.dialogRows[11];
		var permissionChoices: TuiDialogRow = TuiScaffold.dialogRows[13];
		var modelAction: TuiDialogRow = TuiScaffold.dialogRows[16];
		var providerAction: TuiDialogRow = TuiScaffold.dialogRows[17];
		var sessionAction: TuiDialogRow = TuiScaffold.dialogRows[18];
		var permissionAllowAction: TuiDialogRow = TuiScaffold.dialogRows[19];
		var permissionRejectAction: TuiDialogRow = TuiScaffold.dialogRows[20];
		var tmp: JSX.Element = <text fg={theme.primary}>OpenCodeHX TUI</text>;
		var tmp1: JSX.Element = <text>{"Route: " + routeLabel}</text>;
		var tmp2: JSX.Element = <text>{"Theme: " + TuiScaffold.foundation.theme.selected() + " " + TuiScaffold.foundation.theme.mode()}</text>;
		var tmp3: JSX.Element = <text>{"Key: " + key}</text>;
		var tmp4: JSX.Element = <text>{user.label + ": " + user.text}</text>;
		var tmp5: JSX.Element = <text>{tool.label + ": " + tool.text}</text>;
		var tmp6: JSX.Element = <text>{assistant.label + ": " + assistant.text}</text>;
		var tmp7: JSX.Element = <text>{meta.label + ": " + meta.text}</text>;
		var tmp8: JSX.Element = <text>{modelTitle.label + ": " + modelTitle.text}</text>;
		var tmp9: JSX.Element = <text>{modelOption.label + ": " + modelOption.text}</text>;
		var tmp10: JSX.Element = <text>{providerTitle.label + ": " + providerTitle.text}</text>;
		var tmp11: JSX.Element = <text>{providerOption.label + ": " + providerOption.text}</text>;
		var tmp12: JSX.Element = <text>{sessionTitle.label + ": " + sessionTitle.text}</text>;
		var tmp13: JSX.Element = <text>{sessionOption.label + ": " + sessionOption.text}</text>;
		var tmp14: JSX.Element = <text>{permissionTitle.label + ": " + permissionTitle.text}</text>;
		var tmp15: JSX.Element = <text>{permissionRequest.label + ": " + permissionRequest.text}</text>;
		var tmp16: JSX.Element = <text>{permissionChoices.label + ": " + permissionChoices.text}</text>;
		var tmp17: JSX.Element = <text>{modelAction.label + ": " + modelAction.text}</text>;
		var tmp18: JSX.Element = <text>{providerAction.label + ": " + providerAction.text}</text>;
		var tmp19: JSX.Element = <text>{sessionAction.label + ": " + sessionAction.text}</text>;
		var tmp20: JSX.Element = <text>{permissionAllowAction.label + ": " + permissionAllowAction.text}</text>;
		var tmp21: JSX.Element = <text>{permissionRejectAction.label + ": " + permissionRejectAction.text}</text>;
		var tmp22: JSX.Element = <input focused value="" />;
		return <box flexDirection="column">{tmp}{tmp1}{tmp2}{tmp3}{tmp4}{tmp5}{tmp6}{tmp7}{tmp8}{tmp9}{tmp10}{tmp11}{tmp12}{tmp13}{tmp14}{tmp15}{tmp16}{tmp17}{tmp18}{tmp19}{tmp20}{tmp21}{tmp22}</box>;
	}
	static contains(frame: string, expected: string, label: string): void {
		if (frame.indexOf(expected) == -1) {
			throw Exception.thrown("" + label + ": expected frame to contain \"" + expected + "\", got:\n" + frame);
		};
	}
	static parsed(name: string, ctrl?: boolean, meta?: boolean, shift?: boolean, superKey?: boolean): TuiParsedKey {
		if (ctrl == null) {
			ctrl = false;
		};
		if (meta == null) {
			meta = false;
		};
		if (shift == null) {
			shift = false;
		};
		if (superKey == null) {
			superKey = false;
		};
		return {"name": name, "ctrl": ctrl, "meta": meta, "shift": shift, "superKey": superKey};
	}
	static assertEquals<T>(expected: T, actual: T, label: string): void {
		if (actual != expected) {
			throw Exception.thrown("" + label + ": expected " + Std.string(expected) + ", got " + Std.string(actual));
		};
	}
	static assertAction(expected: string, actual: TuiDialogAction, label: string): void {
		TuiScaffold.assertEquals(expected, TuiDialogReplay.actionText(actual), label);
	}
	static get __name__(): string {
		return "opencodehx.tui.TuiScaffold"
	}
	get __class__(): Function {
		return TuiScaffold
	}
}

TuiScaffold.foundation = TuiFoundation.demo()
TuiScaffold.transcriptRows = TuiSessionTranscript.rows(TuiSessionTranscript.fakeProviderToolFixture())
TuiScaffold.dialogRows = TuiDialogReplay.fixtureRows()