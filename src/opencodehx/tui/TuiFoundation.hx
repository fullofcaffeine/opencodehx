package opencodehx.tui;

import opencodehx.tui.TuiKeybind.TuiKeybindRegistry;
import opencodehx.tui.TuiKeybind.TuiParsedKey;
import opencodehx.tui.TuiRoute.TuiRoute;
import opencodehx.tui.TuiRoute.TuiRouteStore;
import opencodehx.tui.TuiTheme.TuiThemeStore;

enum abstract TuiDispatchResult(String) to String {
	var None = "none";
	var Leader = "leader";
	var ThemeList = "theme_list";
}

class TuiFoundation {
	public final route:TuiRouteStore;
	public final theme:TuiThemeStore;
	public final keybind:TuiKeybindRegistry;

	var leaderActive:Bool;

	public function new(route:TuiRouteStore, theme:TuiThemeStore, keybind:TuiKeybindRegistry) {
		this.route = route;
		this.theme = theme;
		this.keybind = keybind;
		leaderActive = false;
	}

	public static function demo():TuiFoundation {
		return new TuiFoundation(TuiRouteStore.demo(), TuiThemeStore.demo(), TuiKeybindRegistry.defaults());
	}

	public function dispatchKey(key:TuiParsedKey):TuiDispatchResult {
		if (!leaderActive && keybind.match("leader", key)) {
			leaderActive = true;
			return Leader;
		}

		final matchedThemeList = keybind.match("theme_list", key, leaderActive);
		leaderActive = false;
		if (matchedThemeList) {
			route.navigate(TuiRoutes.plugin("themes"));
			return ThemeList;
		}

		return None;
	}

	public function leader():Bool {
		return leaderActive;
	}

	public function summary():String {
		final tokens = theme.current();
		return 'route=${route.currentName()} theme=${theme.selected()} mode=${theme.mode()} primary=${tokens.primary} key=${keybind.print("theme_list")}';
	}
}
