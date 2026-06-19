package opencodehx.tui;

enum abstract TuiThemeMode(String) to String {
	var Dark = "dark";
	var Light = "light";
}

typedef TuiThemeTokens = {
	final primary:String;
	final text:String;
	final textMuted:String;
	final background:String;
}

typedef TuiThemeInfo = {
	final name:String;
	final tokens:TuiThemeTokens;
}

class TuiThemeStore {
	final themes:Array<TuiThemeInfo>;
	var selectedName:String;
	var currentMode:TuiThemeMode;

	public function new(themes:Array<TuiThemeInfo>, selectedName:String, mode:TuiThemeMode) {
		if (themes.length == 0)
			throw "TUI theme store requires at least one theme";
		this.themes = themes.copy();
		this.selectedName = selectedName;
		currentMode = mode;
		if (!has(selectedName))
			this.selectedName = themes[0].name;
	}

	public static function demo():TuiThemeStore {
		return new TuiThemeStore([
			{
				name: "opencode",
				tokens: {
					primary: "#f97316",
					text: "#f8fafc",
					textMuted: "#94a3b8",
					background: "#0f172a",
				},
			},
			{
				name: "paper",
				tokens: {
					primary: "#2563eb",
					text: "#111827",
					textMuted: "#6b7280",
					background: "#ffffff",
				},
			},
		], "opencode", Dark);
	}

	public function ready():Bool {
		return true;
	}

	public function selected():String {
		return selectedName;
	}

	public function mode():TuiThemeMode {
		return currentMode == Dark ? Dark : Light;
	}

	public function setMode(mode:TuiThemeMode):Void {
		currentMode = mode;
	}

	public function has(name:String):Bool {
		for (theme in themes) {
			if (theme.name == name)
				return true;
		}
		return false;
	}

	public function set(name:String):Bool {
		if (!has(name))
			return false;
		selectedName = name;
		return true;
	}

	public function current():TuiThemeTokens {
		for (theme in themes) {
			if (theme.name == selectedName)
				return theme.tokens;
		}
		return themes[0].tokens;
	}
}
