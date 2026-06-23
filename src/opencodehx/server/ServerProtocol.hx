package opencodehx.server;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end
import genes.ts.Unknown;
import opencodehx.session.SessionID;
import opencodehx.session.SessionInfo.SessionInfo;

typedef CreateSessionRequest = {
	final prompt:String;
	final title:String;
	final parentID:Null<String>;
}

typedef SelectSessionRequest = {
	final sessionID:String;
}

typedef UpdateSessionRequest = {
	final title:Null<String>;
	final archived:Null<Float>;
}

typedef SessionListQuery = {
	final directory:Null<String>;
	final roots:Bool;
	final start:Null<Float>;
	final cursor:Null<Float>;
	final search:Null<String>;
	final limit:Int;
	final archived:Bool;
}

typedef ServerErrorResponse = {
	final error:String;
}

typedef ServerEventProperties = {
	@:optional final sessionID:String;
}

typedef ServerEvent = {
	final type:ServerEventType;
	final properties:ServerEventProperties;
}

enum abstract ServerEventType(String) to String {
	var ServerConnected = "server.connected";
	var ServerHeartbeat = "server.heartbeat";
	var SessionCreated = "session.created";
	var SessionSelected = "session.selected";
}

class ServerEventTypes {
	public static function fromBoundary(type:String):Null<ServerEventType> {
		return switch type {
			case "server.connected": ServerConnected;
			case "server.heartbeat": ServerHeartbeat;
			case "session.created": SessionCreated;
			case "session.selected": SessionSelected;
			case _: null;
		}
	}

	public static macro function known(type:Expr):Expr {
		final eventType = literalString(type);
		final entries = eventEntries();
		for (entry in entries) {
			if (entry.value == eventType) {
				final eventExpr:Expr = {
					expr: EField(macro opencodehx.server.ServerProtocol.ServerEventType, entry.fieldName),
					pos: type.pos,
				};
				final out = macro $eventExpr;
				out.pos = type.pos;
				return out;
			}
		}

		Context.error('Unknown source-authored server event type "${eventType}". Known server event types: ${knownEventTypes(entries)}.', type.pos);
		return macro null;
	}

	#if macro
	static function eventEntries():Array<{final fieldName:String; final value:String;}> {
		return switch Context.getType("opencodehx.server.ServerProtocol.ServerEventType") {
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

	static function knownEventTypes(entries:Array<{final fieldName:String; final value:String;}>):String {
		return [for (entry in entries) entry.value].join(", ");
	}

	static function literalString(expr:Expr):String {
		return switch expr.expr {
			case EConst(CString(value, _)):
				value;
			default:
				Context.error("Source-authored server event types must be string literals so the event catalog can be checked at compile time.", expr.pos);
		}
	}
	#end
}

typedef SessionResponseTime = {
	final created:Float;
	final updated:Float;
}

typedef SessionResponse = {
	final id:String;
	final projectID:String;
	final workspaceID:Null<String>;
	final parentID:Null<String>;
	final slug:String;
	final directory:String;
	final title:String;
	final version:String;
	final time:SessionResponseTime;
}

typedef ProjectResponse = {
	final id:String;
	final worktree:String;
	final name:Null<String>;
}

typedef GlobalSessionResponse = {
	> SessionResponse,
	final project:Null<ProjectResponse>;
}

enum DecodeResult<T> {
	Decoded(value:T);
	Rejected(message:String);
}

class ServerProtocol {
	public static inline final DEFAULT_PROMPT = "Say hello from the fixture.";
	public static inline final DEFAULT_LIMIT = 100000;

	public static function decodeCreateSession(raw:Unknown):DecodeResult<CreateSessionRequest> {
		return switch optionalString(raw, "prompt") {
			case Rejected(message):
				Rejected(message);
			case Decoded(rawPrompt):
				final prompt = emptyToDefault(rawPrompt, DEFAULT_PROMPT);
				switch optionalString(raw, "title") {
					case Rejected(message):
						Rejected(message);
					case Decoded(rawTitle):
						switch optionalString(raw, "parentID") {
							case Rejected(message):
								Rejected(message);
							case Decoded(parentID):
								final parentIDValid = parentID == null || StringTools.startsWith(parentID, "ses_");
								if (!parentIDValid) Rejected("Invalid parent session ID"); else Decoded({
									prompt: prompt,
									title: emptyToDefault(rawTitle, prompt),
									parentID: parentID,
								});
						}
				}
		}
	}

	public static function decodeSelectSession(raw:Unknown):DecodeResult<SelectSessionRequest> {
		return switch optionalString(raw, "sessionID") {
			case Rejected(_):
				Rejected("Invalid session ID");
			case Decoded(value):
				if (value == null || !StringTools.startsWith(value, "ses_")) Rejected("Invalid session ID"); else Decoded({sessionID: value});
		}
	}

	public static function decodeUpdateSession(raw:Unknown):DecodeResult<UpdateSessionRequest> {
		return switch optionalString(raw, "title") {
			case Rejected(message):
				Rejected(message);
			case Decoded(title):
				switch optionalNestedFloat(raw, "time", "archived") {
					case Rejected(message):
						Rejected(message);
					case Decoded(archived):
						Decoded({title: title, archived: archived});
				}
		}
	}

	public static function decodeSessionListQuery(read:String->Null<String>):SessionListQuery {
		return {
			directory: blankToNull(read("directory")),
			roots: read("roots") == "true",
			start: parseOptionalFloat(read("start")),
			cursor: parseOptionalFloat(read("cursor")),
			search: blankToNull(read("search")),
			limit: parseLimit(read("limit")),
			archived: read("archived") == "true",
		};
	}

	public static function matchesSession(info:SessionInfo, query:SessionListQuery):Bool {
		if (query.directory != null && info.directory != query.directory)
			return false;
		if (query.roots && info.parentID != null)
			return false;
		if (query.start != null && info.time.updated < query.start)
			return false;
		if (query.cursor != null && info.time.updated >= query.cursor)
			return false;
		if (query.search != null && query.search != "") {
			final haystack = info.title.toLowerCase();
			if (haystack.indexOf(query.search.toLowerCase()) == -1)
				return false;
		}
		return true;
	}

	public static function matchesGlobalSession(info:SessionInfo, query:SessionListQuery):Bool {
		if (!query.archived && info.time.archived != null)
			return false;
		return matchesSession(info, query);
	}

	public static function withTitle(info:SessionInfo, title:String, ?updated:Float):SessionInfo {
		return {
			id: info.id,
			slug: info.slug,
			projectID: info.projectID,
			workspaceID: info.workspaceID,
			directory: info.directory,
			parentID: info.parentID,
			title: title,
			version: info.version,
			summary: info.summary,
			share: info.share,
			revert: info.revert,
			permission: info.permission,
			time: {
				created: info.time.created,
				updated: updated == null ? info.time.updated : updated,
				compacting: info.time.compacting,
				archived: info.time.archived,
			},
		};
	}

	public static function withArchived(info:SessionInfo, archived:Null<Float>, ?updated:Float):SessionInfo {
		return {
			id: info.id,
			slug: info.slug,
			projectID: info.projectID,
			workspaceID: info.workspaceID,
			directory: info.directory,
			parentID: info.parentID,
			title: info.title,
			version: info.version,
			summary: info.summary,
			share: info.share,
			revert: info.revert,
			permission: info.permission,
			time: {
				created: info.time.created,
				updated: updated == null ? info.time.updated : updated,
				compacting: info.time.compacting,
				archived: archived,
			},
		};
	}

	public static function withCreateRequest(info:SessionInfo, request:CreateSessionRequest, directory:String, ?updated:Float):SessionInfo {
		return {
			id: info.id,
			slug: info.slug,
			projectID: info.projectID,
			workspaceID: info.workspaceID,
			directory: directory,
			parentID: request.parentID == null ? info.parentID : SessionID.make(request.parentID),
			title: request.title,
			version: info.version,
			summary: info.summary,
			share: info.share,
			revert: info.revert,
			permission: info.permission,
			time: {
				created: info.time.created,
				updated: updated == null ? info.time.updated : updated,
				compacting: info.time.compacting,
				archived: info.time.archived,
			},
		};
	}

	public static function encodeSession(info:SessionInfo):SessionResponse {
		return {
			id: info.id.toString(),
			projectID: info.projectID,
			workspaceID: info.workspaceID,
			parentID: info.parentID == null ? null : info.parentID.toString(),
			slug: info.slug,
			directory: info.directory,
			title: info.title,
			version: info.version,
			time: {
				created: info.time.created,
				updated: info.time.updated,
			},
		};
	}

	public static function encodeGlobalSession(info:SessionInfo):GlobalSessionResponse {
		final encoded = encodeSession(info);
		return {
			id: encoded.id,
			projectID: encoded.projectID,
			workspaceID: encoded.workspaceID,
			parentID: encoded.parentID,
			slug: encoded.slug,
			directory: encoded.directory,
			title: encoded.title,
			version: encoded.version,
			time: encoded.time,
			project: {
				id: info.projectID,
				worktree: info.directory,
				name: null,
			},
		};
	}

	public static inline function error(message:String):ServerErrorResponse {
		return {error: message};
	}

	public static inline function connectedEvent():ServerEvent {
		return {type: ServerConnected, properties: {}};
	}

	public static inline function heartbeatEvent():ServerEvent {
		return {type: ServerHeartbeat, properties: {}};
	}

	public static inline function sessionEvent(type:ServerEventType, sessionID:String):ServerEvent {
		return {type: type, properties: {sessionID: sessionID}};
	}

	static function optionalString(raw:Unknown, field:String):DecodeResult<Null<String>> {
		// Justified Dynamic boundary: Hono request JSON is generated TS
		// `unknown`, and Haxe Reflect can only inspect object fields through
		// Dynamic. Keep the cast local, guard every field read, and return typed
		// route DTOs instead of leaking Dynamic into route logic.
		final data:Dynamic = cast raw;
		if (data == null || !Reflect.hasField(data, field) || Reflect.field(data, field) == null)
			return Decoded(null);
		final value:Dynamic = Reflect.field(data, field);
		if (!Std.isOfType(value, String))
			return Rejected('${field}: expected string');
		return Decoded(value);
	}

	static function optionalNestedFloat(raw:Unknown, parent:String, field:String):DecodeResult<Null<Float>> {
		// Justified Dynamic boundary: Hono request JSON arrives as `unknown`;
		// the nested update DTO is immediately narrowed to `Null<Float>`.
		final data:Dynamic = cast raw;
		if (data == null || !Reflect.hasField(data, parent) || Reflect.field(data, parent) == null)
			return Decoded(null);
		final nested:Dynamic = Reflect.field(data, parent);
		if (!Reflect.isObject(nested))
			return Rejected('${parent}: expected object');
		if (!Reflect.hasField(nested, field) || Reflect.field(nested, field) == null)
			return Decoded(null);
		final value:Dynamic = Reflect.field(nested, field);
		if (!Std.isOfType(value, Int) && !Std.isOfType(value, Float))
			return Rejected('${parent}.${field}: expected number');
		final parsed = Std.parseFloat(Std.string(value));
		return Math.isNaN(parsed) ? Rejected('${parent}.${field}: expected number') : Decoded(parsed);
	}

	static function emptyToDefault(value:Null<String>, fallback:String):String {
		if (value == null || StringTools.trim(value) == "")
			return fallback;
		return value;
	}

	static function blankToNull(value:Null<String>):Null<String> {
		if (value == null || StringTools.trim(value) == "")
			return null;
		return value;
	}

	static function parseLimit(value:Null<String>):Int {
		if (value == null || value == "")
			return DEFAULT_LIMIT;
		final parsed = Std.parseInt(value);
		if (parsed == null || parsed <= 0)
			return DEFAULT_LIMIT;
		return parsed;
	}

	static function parseOptionalFloat(value:Null<String>):Null<Float> {
		if (value == null || value == "")
			return null;
		final parsed = Std.parseFloat(value);
		return Math.isNaN(parsed) ? null : parsed;
	}
}
