package opencodehx.sdk;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownRecord;
import genes.ts.UnknownNarrow;
import haxe.DynamicAccess;
import haxe.Json;
import js.lib.Promise;
import opencodehx.externs.web.GlobalFetch;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.externs.web.WebStreams.WebResponseStreams;
import opencodehx.externs.web.WebStreams.WebTextDecoder;
import opencodehx.session.MessageCodec;
import opencodehx.session.MessageTypes.WithParts;
import opencodehx.server.ServerProtocol.ServerEvent;
import opencodehx.server.ServerProtocol.ServerEventProperties;
import opencodehx.server.ServerProtocol.ServerEventTypes;
import opencodehx.server.ServerProtocol.SessionResponse;
import opencodehx.server.ServerProtocol.SessionStatusInfo;
import opencodehx.server.ServerProtocol.SessionStatusType;
import opencodehx.server.ServerProtocol.SessionStatusTypes;

typedef CompatClientConfig = {
	final baseUrl:String;
	@:optional final directory:String;
	@:optional final workspace:String;
}

typedef CompatCreateSession = {
	final prompt:String;
	@:optional final title:String;
}

typedef CompatMessagePage = {
	final items:Array<WithParts>;
	@:optional final cursor:String;
	@:optional final link:String;
}

class OpenCodeCompatClient {
	final baseUrl:String;
	final directory:Null<String>;
	final workspace:Null<String>;

	public function new(config:CompatClientConfig) {
		baseUrl = trimRight(config.baseUrl, "/");
		directory = config.directory;
		workspace = config.workspace;
	}

	@:async
	public function createSession(input:CompatCreateSession):Promise<SessionResponse> {
		final headers = jsonHeaders();
		addRoutingHeaders(headers);
		final body = new DynamicAccess<String>();
		body.set("prompt", input.prompt);
		if (input.title != null)
			body.set("title", input.title);
		final response = @:await GlobalFetch.response(url("/session"), {
			method: "POST",
			headers: headers,
			body: Json.stringify(body),
		});
		return decodeSession(@:await response.json(), "create session");
	}

	@:async
	public function listSessions(?limit:Int):Promise<Array<SessionResponse>> {
		final response = @:await GlobalFetch.response(getUrl("/session", limit), {
			method: "GET",
			headers: jsonHeaders(),
		});
		final raw = Unknown.fromBoundary(@:await response.json());
		final items = UnknownNarrow.array(raw);
		if (items == null)
			throw "list sessions: expected array";
		final out:Array<SessionResponse> = [];
		for (index in 0...items.length) {
			out.push(decodeSession(items.get(index), "list session"));
		}
		return out;
	}

	@:async
	public function events(count:Int):Promise<Array<ServerEvent>> {
		final response = @:await GlobalFetch.response(getUrl("/event"), {method: "GET", headers: jsonHeaders()});
		final body = WebResponseStreams.body(response);
		if (body == null)
			throw "event stream missing body";
		return @:await readEvents(body, count);
	}

	@:async
	public function selectSession(sessionID:String):Promise<Bool> {
		final body = new DynamicAccess<String>();
		body.set("sessionID", sessionID);
		final response = @:await GlobalFetch.response(url("/tui/select-session"), {
			method: "POST",
			headers: jsonHeaders(),
			body: Json.stringify(body),
		});
		return @:await response.json() == true;
	}

	@:async
	public function messages(sessionID:String, ?limit:Int, ?before:String):Promise<CompatMessagePage> {
		final params:Array<String> = [];
		if (limit != null)
			params.push("limit=" + Std.string(limit));
		if (before != null && before != "")
			params.push("before=" + StringTools.urlEncode(before));
		final suffix = params.length == 0 ? "" : "?" + params.join("&");
		final response = @:await GlobalFetch.response(url("/session/" + StringTools.urlEncode(sessionID) + "/message") + suffix, {
			method: "GET",
			headers: jsonHeaders(),
		});
		final raw = Unknown.fromBoundary(@:await response.json());
		final items = UnknownNarrow.array(raw);
		if (items == null)
			throw "session messages: expected array";
		final out:Array<WithParts> = [];
		for (index in 0...items.length) {
			out.push(MessageCodec.decodeWithParts(cast items.get(index), 'session messages[${index}]'));
		}
		final cursor:Null<String> = response.headers.get("x-next-cursor");
		final link:Null<String> = response.headers.get("link");
		final hasCursor = cursor != null && cursor != "";
		final hasLink = link != null && link != "";
		if (hasCursor && hasLink)
			return {items: out, cursor: cursor, link: link};
		if (hasCursor)
			return {items: out, cursor: cursor};
		if (hasLink)
			return {items: out, link: link};
		return {items: out};
	}

	function getUrl(path:String, ?limit:Int):String {
		final params:Array<String> = [];
		if (directory != null && directory != "")
			params.push("directory=" + StringTools.urlEncode(directory));
		if (workspace != null && workspace != "")
			params.push("workspace=" + StringTools.urlEncode(workspace));
		if (limit != null)
			params.push("limit=" + Std.string(limit));
		final suffix = params.length == 0 ? "" : "?" + params.join("&");
		return url(path) + suffix;
	}

	function url(path:String):String {
		return baseUrl + path;
	}

	function addRoutingHeaders(headers:DynamicAccess<String>):Void {
		if (directory != null && directory != "")
			headers.set("x-opencode-directory", StringTools.urlEncode(directory));
		if (workspace != null && workspace != "")
			headers.set("x-opencode-workspace", workspace);
	}

	@:async
	static function readEvents(body:WebReadableStream<js.lib.Uint8Array>, count:Int):Promise<Array<ServerEvent>> {
		final reader = body.getReader();
		final decoder = new WebTextDecoder();
		var text = "";
		try {
			while (parseEvents(text).length < count) {
				final result = @:await reader.read();
				if (result.done)
					break;
				if (result.value != null)
					text += decoder.decode(result.value, {stream: true});
			}
			@:await reader.cancel();
			return parseEvents(text);
		} catch (error:Dynamic) {
			@:await reader.cancel();
			throw error;
		}
	}

	static function parseEvents(text:String):Array<ServerEvent> {
		final out:Array<ServerEvent> = [];
		for (frame in text.split("\n\n")) {
			final trimmed = StringTools.trim(frame);
			if (trimmed == "")
				continue;
			for (line in trimmed.split("\n")) {
				if (!StringTools.startsWith(line, "data: "))
					continue;
				out.push(decodeEvent(Unknown.fromBoundary(Json.parse(line.substr(6)))));
			}
		}
		return out;
	}

	static function decodeSession(raw:Unknown, label:String):SessionResponse {
		final record = requireRecord(raw, label);
		final time = requireRecord(record.get("time"), label + ".time");
		return {
			id: requireString(record, "id", label),
			projectID: requireString(record, "projectID", label),
			workspaceID: UnknownNarrow.string(record.get("workspaceID")),
			parentID: UnknownNarrow.string(record.get("parentID")),
			slug: requireString(record, "slug", label),
			directory: requireString(record, "directory", label),
			title: requireString(record, "title", label),
			version: requireString(record, "version", label),
			time: {
				created: requireFloat(time, "created", label + ".time"),
				updated: requireFloat(time, "updated", label + ".time"),
			},
		};
	}

	static function decodeEvent(raw:Unknown):ServerEvent {
		final record = requireRecord(raw, "event");
		final propertiesRaw = record.get("properties");
		final properties = UnknownNarrow.record(propertiesRaw);
		final sessionID = properties == null ? null : UnknownNarrow.string(properties.get("sessionID"));
		final status = properties == null ? null : decodeStatus(properties.get("status"), "event.properties.status");
		final typeText = requireString(record, "type", "event");
		final eventType = ServerEventTypes.fromBoundary(typeText);
		if (eventType == null)
			throw 'event.type: unknown server event type ${typeText}';
		return {
			type: eventType,
			properties: eventProperties(sessionID, status),
		};
	}

	static function eventProperties(sessionID:Null<String>, status:Null<SessionStatusInfo>):ServerEventProperties {
		if (sessionID != null && status != null)
			return {sessionID: sessionID, status: status};
		if (sessionID != null)
			return {sessionID: sessionID};
		if (status != null)
			return {status: status};
		return {};
	}

	static function decodeStatus(raw:Unknown, label:String):Null<SessionStatusInfo> {
		final record = UnknownNarrow.record(raw);
		if (record == null)
			return null;
		final typeText = requireString(record, "type", label);
		final statusType = SessionStatusTypes.fromBoundary(typeText);
		if (statusType == null)
			throw '${label}.type: unknown session status ${typeText}';
		if (statusType == SessionStatusType.Retry) {
			return {
				type: statusType,
				attempt: Std.int(requireFloat(record, "attempt", label)),
				message: requireString(record, "message", label),
				next: requireFloat(record, "next", label),
			};
		}
		return {type: statusType};
	}

	static function requireRecord(raw:Unknown, label:String):UnknownRecord {
		final record = UnknownNarrow.record(raw);
		if (record == null)
			throw '${label}: expected object';
		return record;
	}

	static function requireString(record:UnknownRecord, field:String, label:String):String {
		final value = UnknownNarrow.string(record.get(field));
		if (value == null)
			throw '${label}.${field}: expected string';
		return value;
	}

	static function requireFloat(record:UnknownRecord, field:String, label:String):Float {
		final value = UnknownNarrow.number(record.get(field));
		if (value == null)
			throw '${label}.${field}: expected number';
		return value;
	}

	static function jsonHeaders():DynamicAccess<String> {
		final headers = new DynamicAccess<String>();
		headers.set("content-type", "application/json");
		return headers;
	}

	static function trimRight(value:String, suffix:String):String {
		if (StringTools.endsWith(value, suffix))
			return value.substr(0, value.length - suffix.length);
		return value;
	}
}
