package opencodehx.tui;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end
import opencodehx.tui.TuiRoute.TuiPluginRoute;
import opencodehx.tui.TuiRoute.TuiPluginRouteName;

class TuiRoutes {
	public static function builtinPlugins():Array<TuiPluginRoute> {
		return [{name: Themes, label: "Theme List"}];
	}

	public static macro function plugin(name:Expr):Expr {
		final routeName = literalString(name);
		final entries = pluginRouteEntries();
		for (entry in entries) {
			if (entry.value == routeName) {
				final routeNameExpr:Expr = {
					expr: EField(macro opencodehx.tui.TuiRoute.TuiPluginRouteName, entry.fieldName),
					pos: name.pos,
				};
				final out = macro opencodehx.tui.TuiRoute.TuiRoute.Plugin($routeNameExpr);
				out.pos = name.pos;
				return out;
			}
		}

		Context.error('Unknown TUI plugin route "${routeName}". Known plugin routes: ${knownRouteNames(entries)}.', name.pos);
		return macro null;
	}

	#if macro
	static function pluginRouteEntries():Array<{final fieldName:String; final value:String;}> {
		return switch Context.getType("opencodehx.tui.TuiRoute.TuiPluginRouteName") {
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

	static function knownRouteNames(entries:Array<{final fieldName:String; final value:String;}>):String {
		return [for (entry in entries) entry.value].join(", ");
	}

	static function literalString(expr:Expr):String {
		return switch expr.expr {
			case EConst(CString(value, _)):
				value;
			default:
				Context.error("TUI plugin route names must be string literals so the route catalog can be checked at compile time.", expr.pos);
		}
	}
	#end
}
