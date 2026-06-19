import type {JSX} from "@opentui/solid"
import type {TuiThemeTokens} from "./TuiTheme.js"
import type {TuiParsedKey} from "./TuiKeybind.js"
import {TuiFoundation} from "./TuiFoundation.js"
import type {OpenTuiTestRender} from "../externs/opentui/OpenTuiSolid.js"
import {Exception} from "../../haxe/Exception.js"
import {Register} from "../../genes/Register.js"
import {Std} from "../../Std.js"
import * as OpenTuiSolid from "@opentui/solid"

export class TuiScaffold {
	declare static foundation: TuiFoundation;
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
		var rendered: OpenTuiTestRender = await OpenTuiSolid.testRender(TuiScaffold.renderView,{ width : 40, height : 8});
		await rendered.renderOnce();
		var first: string = rendered.captureCharFrame();
		TuiScaffold.contains(first, "OpenCodeHX TUI", "static title");
		TuiScaffold.contains(first, "Theme List", "plugin route label");
		TuiScaffold.contains(first, "ctrl+x t", "keybind metadata");
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
		var tmp: JSX.Element = <text fg={theme.primary}>OpenCodeHX TUI</text>;
		var tmp1: JSX.Element = <text>{"Route: " + routeLabel}</text>;
		var tmp2: JSX.Element = <text>{"Theme: " + TuiScaffold.foundation.theme.selected() + " " + TuiScaffold.foundation.theme.mode()}</text>;
		var tmp3: JSX.Element = <text>{"Key: " + key}</text>;
		var tmp4: JSX.Element = <input focused value="" />;
		return <box flexDirection="column">{tmp}{tmp1}{tmp2}{tmp3}{tmp4}</box>;
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
	static get __name__(): string {
		return "opencodehx.tui.TuiScaffold"
	}
	get __class__(): Function {
		return TuiScaffold
	}
}

TuiScaffold.foundation = TuiFoundation.demo()