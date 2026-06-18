package opencodehx.server;

import genes.ts.Unknown;
import opencodehx.session.SessionInfo.SessionInfo;

typedef CreateSessionRequest = {
	final prompt:String;
	final title:String;
}

typedef SelectSessionRequest = {
	final sessionID:String;
}

typedef SessionListQuery = {
	final directory:Null<String>;
	final roots:Bool;
	final start:Null<Float>;
	final search:Null<String>;
	final limit:Int;
}

typedef ServerErrorResponse = {
	final error:String;
}

typedef ServerEventProperties = {
	@:optional final sessionID:String;
}

typedef ServerEvent = {
	final type:String;
	final properties:ServerEventProperties;
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
						Decoded({
							prompt: prompt,
							title: emptyToDefault(rawTitle, prompt),
						});
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

	public static function decodeSessionListQuery(read:String->Null<String>):SessionListQuery {
		return {
			directory: blankToNull(read("directory")),
			roots: read("roots") == "true",
			start: parseOptionalFloat(read("start")),
			search: blankToNull(read("search")),
			limit: parseLimit(read("limit")),
		};
	}

	public static function matchesSession(info:SessionInfo, query:SessionListQuery):Bool {
		if (query.directory != null && info.directory != query.directory)
			return false;
		if (query.roots && info.parentID != null)
			return false;
		if (query.start != null && info.time.created < query.start)
			return false;
		if (query.search != null && query.search != "") {
			final haystack = info.title.toLowerCase();
			if (haystack.indexOf(query.search.toLowerCase()) == -1)
				return false;
		}
		return true;
	}

	public static function withTitle(info:SessionInfo, title:String):SessionInfo {
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
			time: info.time,
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

	public static inline function error(message:String):ServerErrorResponse {
		return {error: message};
	}

	public static inline function connectedEvent():ServerEvent {
		return {type: "server.connected", properties: {}};
	}

	public static inline function heartbeatEvent():ServerEvent {
		return {type: "server.heartbeat", properties: {}};
	}

	public static inline function sessionEvent(type:String, sessionID:String):ServerEvent {
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
