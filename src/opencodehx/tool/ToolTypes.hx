package opencodehx.tool;

import genes.ts.Json;
import genes.ts.JsonValue;
import genes.ts.Unknown;
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
	final metadata:ToolPermissionMetadata;
}

typedef ToolPermissionDecision = {
	final allowed:Bool;
	@:optional final reason:String;
}

typedef ToolResult = {
	final title:String;
	final output:String;
	final metadata:ToolResultMetadata;
	@:optional final attachments:Array<ToolResultAttachment>;
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
	final execute:(ToolCallInput, ToolContext) -> ToolResult;
}

typedef ToolInfo = {
	final id:String;
	final init:Void->ToolDef;
}

abstract ToolCallInput(Unknown) from Unknown to Unknown {
	inline function new(value:Unknown) {
		this = value;
	}

	@:from public static inline function fromBoundary<T>(value:T):ToolCallInput {
		return new ToolCallInput(Unknown.fromBoundary(value));
	}

	public inline function unknown():Unknown {
		return this;
	}
}

abstract ToolResultMetadata(JsonValue) from JsonValue to JsonValue {
	inline function new(value:JsonValue) {
		this = value;
	}

	@:from public static inline function fromJson(value:JsonValue):ToolResultMetadata {
		return new ToolResultMetadata(value);
	}

	public static macro function checked(expr:Expr):Expr {
		return macro @:pos(expr.pos) opencodehx.tool.ToolTypes.ToolResultMetadata.fromJson(genes.ts.Json.value($expr));
	}

	public static inline function empty():ToolResultMetadata {
		return new ToolResultMetadata(Json.object({}));
	}
}

abstract ToolPermissionMetadata(JsonValue) from JsonValue to JsonValue {
	inline function new(value:JsonValue) {
		this = value;
	}

	@:from public static inline function fromJson(value:JsonValue):ToolPermissionMetadata {
		return new ToolPermissionMetadata(value);
	}

	public static macro function checked(expr:Expr):Expr {
		return macro @:pos(expr.pos) opencodehx.tool.ToolTypes.ToolPermissionMetadata.fromJson(genes.ts.Json.value($expr));
	}

	public static inline function empty():ToolPermissionMetadata {
		return new ToolPermissionMetadata(Json.object({}));
	}
}

abstract ToolResultAttachment(Unknown) from Unknown to Unknown {
	inline function new(value:Unknown) {
		this = value;
	}

	@:from public static inline function fromBoundary<T>(value:T):ToolResultAttachment {
		return new ToolResultAttachment(Unknown.fromBoundary(value));
	}
}

enum ToolInputDecode<T> {
	Decoded(input:T);
	Invalid(issues:Array<String>);
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
