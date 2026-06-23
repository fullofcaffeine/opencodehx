package opencodehx.tui;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

typedef TuiParsedKey = {
	final name:String;
	final ctrl:Bool;
	final meta:Bool;
	final shift:Bool;
	final superKey:Bool;
}

typedef TuiKeyInfo = {
	final name:String;
	final ctrl:Bool;
	final meta:Bool;
	final shift:Bool;
	final superKey:Bool;
	final leader:Bool;
}

typedef TuiKeybindEntry = {
	final name:String;
	final value:String;
}

enum abstract TuiKeybindActionName(String) to String {
	var Leader = "leader";
	var ThemeList = "theme_list";
	var SessionNew = "session_new";
}

class TuiKeybindActions {
	public static macro function action(name:Expr):Expr {
		final actionName = literalString(name);
		final entries = actionEntries();
		for (entry in entries) {
			if (entry.value == actionName) {
				final actionExpr:Expr = {
					expr: EField(macro opencodehx.tui.TuiKeybind.TuiKeybindActionName, entry.fieldName),
					pos: name.pos,
				};
				final out = macro $actionExpr;
				out.pos = name.pos;
				return out;
			}
		}

		Context.error('Unknown TUI keybind action "${actionName}". Known actions: ${knownActionNames(entries)}.', name.pos);
		return macro null;
	}

	#if macro
	static function actionEntries():Array<{final fieldName:String; final value:String;}> {
		return switch Context.getType("opencodehx.tui.TuiKeybind.TuiKeybindActionName") {
			case TAbstract(_.get() => abstractType, _):
				final impl = abstractType.impl.get();
				final out:Array<{final fieldName:String; final value:String;}> = [];
				for (field in impl.statics.get()) {
					switch field.kind {
						case FVar(_, _):
							final value = typedStringValue(field.expr());
							if (value != null) out.push({fieldName: field.name, value: value});
						default:
					}
				}
				out;
			default:
				[];
		}
	}

	static function typedStringValue(expr:TypedExpr):Null<String> {
		if (expr == null)
			return null;
		return switch expr.expr {
			case TMeta(_, inner) | TParenthesis(inner) | TCast(inner, _):
				typedStringValue(inner);
			case TConst(TString(value)):
				value;
			default:
				null;
		}
	}

	static function knownActionNames(entries:Array<{final fieldName:String; final value:String;}>):String {
		return [for (entry in entries) entry.value].join(", ");
	}

	static function literalString(expr:Expr):String {
		return switch expr.expr {
			case EConst(CString(value, _)):
				value;
			default:
				Context.error("TUI keybind action names must be string literals so the action catalog can be checked at compile time.", expr.pos);
		}
	}
	#end
}

class TuiKeybindRegistry {
	final entries:Array<TuiKeybindEntry>;

	public function new(entries:Array<TuiKeybindEntry>) {
		this.entries = entries.copy();
	}

	public static function defaults():TuiKeybindRegistry {
		return new TuiKeybindRegistry([
			{name: TuiKeybindActionName.Leader, value: "ctrl+x"},
			{name: TuiKeybindActionName.ThemeList, value: "<leader>t"},
			{name: TuiKeybindActionName.SessionNew, value: "<leader>n"},
		]);
	}

	public function all():Array<TuiKeybindEntry> {
		return entries.copy();
	}

	public function configured(name:String):Null<String> {
		for (entry in entries) {
			if (entry.name == name)
				return entry.value;
		}
		return null;
	}

	public function parse(nameOrCombo:String):Array<TuiKeyInfo> {
		final configuredValue = configured(nameOrCombo);
		return parseCombo(configuredValue == null ? nameOrCombo : configuredValue);
	}

	public function match(nameOrCombo:String, key:TuiParsedKey, leader:Bool = false):Bool {
		final parsed = fromParsedKey(key, leader);
		for (candidate in parse(nameOrCombo)) {
			if (matches(candidate, parsed))
				return true;
		}
		return false;
	}

	public function print(nameOrCombo:String):String {
		final first = parse(nameOrCombo)[0];
		if (first == null)
			return "";
		final text = format(first);
		final lead = parse(TuiKeybindActionName.Leader)[0];
		if (lead == null)
			return text;
		return StringTools.replace(text, "<leader>", format(lead));
	}

	public function create(defaults:Array<TuiKeybindEntry>, overrides:Array<TuiKeybindEntry>):TuiPluginKeybind {
		final out:Array<TuiKeybindEntry> = [];
		for (entry in defaults) {
			final overrideValue = findOverride(overrides, entry.name);
			out.push({
				name: entry.name,
				value: overrideValue == null ? entry.value : overrideValue,
			});
		}
		return new TuiPluginKeybind(this, out);
	}

	function findOverride(overrides:Array<TuiKeybindEntry>, name:String):Null<String> {
		for (entry in overrides) {
			if (entry.name == name && StringTools.trim(entry.value).length > 0)
				return entry.value;
		}
		return null;
	}

	public static function parseCombo(combo:String):Array<TuiKeyInfo> {
		if (combo == "none")
			return [];

		final out:Array<TuiKeyInfo> = [];
		for (raw in combo.split(",")) {
			final normalized = StringTools.replace(raw, "<leader>", "leader+");
			final parts = normalized.toLowerCase().split("+");
			var name = "";
			var ctrl = false;
			var meta = false;
			var shift = false;
			var superKey = false;
			var leader = false;

			for (part in parts) {
				switch StringTools.trim(part) {
					case "ctrl":
						ctrl = true;
					case "alt" | "meta" | "option":
						meta = true;
					case "super":
						superKey = true;
					case "shift":
						shift = true;
					case "leader":
						leader = true;
					case "esc":
						name = "escape";
					case "":
					case other:
						name = other;
				}
			}

			out.push({
				name: name,
				ctrl: ctrl,
				meta: meta,
				shift: shift,
				superKey: superKey,
				leader: leader,
			});
		}
		return out;
	}

	public static function fromParsedKey(key:TuiParsedKey, leader:Bool = false):TuiKeyInfo {
		return {
			name: key.name == " " ? "space" : key.name,
			ctrl: key.ctrl,
			meta: key.meta,
			shift: key.shift,
			superKey: key.superKey,
			leader: leader,
		};
	}

	public static function matches(left:TuiKeyInfo, right:TuiKeyInfo):Bool {
		return left.name == right.name && left.ctrl == right.ctrl && left.meta == right.meta && left.shift == right.shift
			&& left.superKey == right.superKey && left.leader == right.leader;
	}

	public static function format(info:TuiKeyInfo):String {
		final parts:Array<String> = [];
		if (info.ctrl)
			parts.push("ctrl");
		if (info.meta)
			parts.push("alt");
		if (info.superKey)
			parts.push("super");
		if (info.shift)
			parts.push("shift");
		if (info.name.length > 0)
			parts.push(info.name == "delete" ? "del" : info.name);

		var result = parts.join("+");
		if (info.leader)
			result = result.length == 0 ? "<leader>" : '<leader> ${result}';
		return result;
	}
}

class TuiPluginKeybind {
	final base:TuiKeybindRegistry;
	final entries:Array<TuiKeybindEntry>;

	public function new(base:TuiKeybindRegistry, entries:Array<TuiKeybindEntry>) {
		this.base = base;
		this.entries = entries.copy();
	}

	public function all():Array<TuiKeybindEntry> {
		return entries.copy();
	}

	public function get(name:String):String {
		for (entry in entries) {
			if (entry.name == name)
				return entry.value;
		}
		return name;
	}

	public function match(name:String, key:TuiParsedKey, leader:Bool = false):Bool {
		return base.match(get(name), key, leader);
	}

	public function print(name:String):String {
		return base.print(get(name));
	}
}
