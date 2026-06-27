package opencodehx.tool;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

typedef ToolContext = {
	final directory:String;
	@:optional final worktree:String;
	@:optional final sessionID:String;
	@:optional final messageID:String;
	@:optional final agent:String;
	@:optional final callID:String;
	@:optional final ask:(ToolPermissionRequest) -> ToolPermissionDecision;
}

typedef ToolPermissionRequest = {
	final permission:String;
	final patterns:Array<String>;
	final always:Array<String>;
	final metadata:Dynamic;
}

typedef ToolPermissionDecision = {
	final allowed:Bool;
	@:optional final reason:String;
}

typedef ToolResult = {
	final title:String;
	final output:String;
	final metadata:Dynamic;
	@:optional final attachments:Array<Dynamic>;
}

typedef ToolParameter = {
	final name:String;
	final type:String;
	final required:Bool;
	@:optional final description:String;
}

typedef ToolSchema = {
	final parameters:Array<ToolParameter>;
}

typedef ToolDef = {
	final id:String;
	final description:String;
	final schema:ToolSchema;
	final execute:(Dynamic, ToolContext) -> ToolResult;
}

typedef ToolInfo = {
	final id:String;
	final init:Void->ToolDef;
}

enum abstract KnownToolID(String) to String {
	var ApplyPatch = "apply_patch";
	var Bash = "bash";
	var Edit = "edit";
	var Glob = "glob";
	var Grep = "grep";
	var Invalid = "invalid";
	var Lsp = "lsp";
	var Read = "read";
	var Write = "write";
}

class ToolIDs {
	public static macro function known(id:Expr):Expr {
		final toolID = literalString(id);
		final entries = toolEntries();
		for (entry in entries) {
			if (entry.value == toolID) {
				final toolExpr:Expr = {
					expr: EField(macro opencodehx.tool.ToolTypes.KnownToolID, entry.fieldName),
					pos: id.pos,
				};
				final out = macro $toolExpr;
				out.pos = id.pos;
				return out;
			}
		}

		Context.error('Unknown source-authored tool id "${toolID}". Known tool ids: ${knownToolIDs(entries)}.', id.pos);
		return macro null;
	}

	#if macro
	static function toolEntries():Array<{final fieldName:String; final value:String;}> {
		return switch Context.getType("opencodehx.tool.ToolTypes.KnownToolID") {
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

	static function knownToolIDs(entries:Array<{final fieldName:String; final value:String;}>):String {
		return [for (entry in entries) entry.value].join(", ");
	}

	static function literalString(expr:Expr):String {
		return switch expr.expr {
			case EConst(CString(value, _)):
				value;
			default:
				Context.error("Source-authored tool ids must be string literals so the tool catalog can be checked at compile time.", expr.pos);
		}
	}
	#end
}
