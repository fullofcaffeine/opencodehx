import type {JSX} from "@opentui/solid"
import type {OpenTuiTestRender} from "../externs/opentui/OpenTuiSolid.js"
import {Exception} from "../../haxe/Exception.js"
import {Register} from "../../genes/Register.js"
import * as OpenTuiSolid from "@opentui/solid"

export class TuiScaffold {
	static main(): void {
		TuiScaffold.run().then(function (_: void) {
			console.log("tui-scaffold:ok");
			return null;
		});
	}
	static async run(): Promise<void> {
		var rendered: OpenTuiTestRender = await OpenTuiSolid.testRender(TuiScaffold.renderView,{ width : 40, height : 8});
		await rendered.renderOnce();
		var first: string = rendered.captureCharFrame();
		TuiScaffold.contains(first, "OpenCodeHX TUI", "static title");
		await rendered.mockInput.typeText("x");
		await rendered.renderOnce();
		var second: string = rendered.captureCharFrame();
		TuiScaffold.contains(second, "x", "typed input");
		rendered.mockInput.pressCtrlC();
		return;
	}
	static renderView(): JSX.Element {
		var tmp: JSX.Element = <text>OpenCodeHX TUI</text>;
		var tmp1: JSX.Element = <input focused value="" />;
		return <box flexDirection="column">{tmp}{tmp1}</box>;
	}
	static contains(frame: string, expected: string, label: string): void {
		if (frame.indexOf(expected) == -1) {
			throw Exception.thrown("" + label + ": expected frame to contain \"" + expected + "\", got:\n" + frame);
		};
	}
	static get __name__(): string {
		return "opencodehx.tui.TuiScaffold"
	}
	get __class__(): Function {
		return TuiScaffold
	}
}
