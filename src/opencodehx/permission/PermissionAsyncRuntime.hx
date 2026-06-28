package opencodehx.permission;

import js.lib.Error;
import js.lib.Promise;
import opencodehx.permission.PermissionTypes.PermissionAskRecord;
import opencodehx.permission.PermissionTypes.PermissionReply;
import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.project.InstanceRuntime;
import opencodehx.project.InstanceRuntime.InstanceContext;
import opencodehx.tool.ToolTypes.ToolPermissionMetadata;

typedef PermissionToolRef = {
	final messageID:String;
	final callID:String;
}

typedef PermissionAskInput = {
	@:optional final id:String;
	final sessionID:String;
	final permission:String;
	final patterns:Array<String>;
	final metadata:ToolPermissionMetadata;
	final always:Array<String>;
	final ruleset:Array<PermissionRule>;
	@:optional final tool:PermissionToolRef;
}

enum PermissionAsyncEvent {
	PermissionAsked(request:PermissionAskRecord);
	PermissionReplied(sessionID:String, requestID:String, reply:String);
	PermissionRejected(sessionID:String, requestID:String);
}

private typedef PendingPermission = {
	final info:PermissionAskRecord;
	final resolve:Bool->Void;
	final reject:Error->Void;
}

/**
 * Raised when permission rules explicitly deny a requested pattern.
 */
class PermissionDeniedError extends Error {
	public function new(rule:PermissionRule) {
		super('The user has specified a rule which prevents this tool call: ${rule.permission} ${rule.pattern} deny');
	}
}

/**
 * Raised when a user rejects a pending permission request without correction.
 */
class PermissionRejectedError extends Error {
	public function new(?message:String) {
		super(message == null ? "The user rejected permission to use this specific tool call." : message);
	}
}

/**
 * Raised when a rejection includes a corrective message for the model/user.
 */
class PermissionCorrectedError extends Error {
	public function new(message:String) {
		super(message);
	}
}

/**
 * Async pending-permission service for upstream permission lifecycle parity.
 *
 * The current tool registry still uses the synchronous `PermissionRuntime`.
 * This service models the live session/service behavior separately: pending
 * queues, replies, same-session cancellation, `always` approvals, directory
 * isolation, and instance disposal cleanup.
 */
class PermissionAsyncService {
	final pending:Map<String, PendingPermission> = new Map();
	final order:Array<String> = [];
	final approved:Array<PermissionRule> = [];
	final events:Array<PermissionAsyncEvent> = [];
	var nextID = 1;
	var disposed = false;

	public function new() {}

	public function ask(input:PermissionAskInput):Promise<Bool> {
		if (disposed)
			return Promise.reject(new PermissionRejectedError());
		final denied = firstDenied(input.permission, input.patterns, input.ruleset);
		if (denied != null)
			return Promise.reject(new PermissionDeniedError(denied));
		if (allAllowed(input.permission, input.patterns, input.ruleset))
			return resolvedVoid();

		final request = makeRecord(input);
		return new Promise<Bool>((resolve, reject) -> {
			final rejectPermission = (error:Error) -> reject(error);
			pending.set(request.id, {
				info: request,
				resolve: resolve,
				reject: rejectPermission,
			});
			order.push(request.id);
			events.push(PermissionAsked(request));
		});
	}

	public function reply(input:{final requestID:String; final reply:PermissionReply;}):Promise<Bool> {
		final existing = pending.get(input.requestID);
		if (existing == null)
			return resolvedVoid();
		switch input.reply.reply {
			case "once":
				resolvePending(existing, input.reply.reply);
			case "always":
				for (pattern in existing.info.always) {
					approved.push({permission: existing.info.permission, pattern: pattern, action: "allow"});
				}
				resolveMatchingSession(existing.info.sessionID, input.reply.reply);
			case "reject":
				rejectSession(existing.info.sessionID, rejectError(input.reply));
			case _:
				rejectSession(existing.info.sessionID, new PermissionRejectedError());
		}
		return resolvedVoid();
	}

	public function list():Promise<Array<PermissionAskRecord>> {
		final out:Array<PermissionAskRecord> = [];
		for (id in order) {
			final existing = pending.get(id);
			if (existing != null)
				out.push(existing.info);
		}
		return Promise.resolve(out);
	}

	public function eventHistory():Array<PermissionAsyncEvent> {
		return events.copy();
	}

	public function dispose():Void {
		if (disposed)
			return;
		disposed = true;
		rejectAll(new PermissionRejectedError());
	}

	function firstDenied(permission:String, patterns:Array<String>, ruleset:Array<PermissionRule>):Null<PermissionRule> {
		for (pattern in patterns) {
			final rule = PermissionRules.evaluate(permission, pattern, [ruleset, approved]);
			if (rule.action == "deny")
				return rule;
		}
		return null;
	}

	function allAllowed(permission:String, patterns:Array<String>, ruleset:Array<PermissionRule>):Bool {
		for (pattern in patterns) {
			final rule = PermissionRules.evaluate(permission, pattern, [ruleset, approved]);
			if (rule.action != "allow")
				return false;
		}
		return true;
	}

	function resolveMatchingSession(sessionID:String, reply:String):Void {
		final ids = order.copy();
		for (id in ids) {
			final existing = pending.get(id);
			if (existing != null
				&& existing.info.sessionID == sessionID
				&& allAllowed(existing.info.permission, existing.info.patterns, []))
				resolvePending(existing, reply);
		}
	}

	function resolvePending(existing:PendingPermission, reply:String):Void {
		remove(existing.info.id);
		events.push(PermissionReplied(existing.info.sessionID, existing.info.id, reply));
		existing.resolve(true);
	}

	function rejectSession(sessionID:String, error:Error):Void {
		final ids = order.copy();
		for (id in ids) {
			final existing = pending.get(id);
			if (existing != null && existing.info.sessionID == sessionID)
				rejectPending(existing, error);
		}
	}

	function rejectAll(error:Error):Void {
		final ids = order.copy();
		for (id in ids) {
			final existing = pending.get(id);
			if (existing != null)
				rejectPending(existing, error);
		}
	}

	function rejectPending(existing:PendingPermission, error:Error):Void {
		remove(existing.info.id);
		events.push(PermissionRejected(existing.info.sessionID, existing.info.id));
		existing.reject(error);
	}

	function makeRecord(input:PermissionAskInput):PermissionAskRecord {
		final id = input.id == null ? nextPermissionID() : input.id;
		final tool = input.tool;
		if (tool != null) {
			return {
				id: id,
				sessionID: input.sessionID,
				permission: input.permission,
				patterns: input.patterns.copy(),
				metadata: input.metadata,
				always: input.always.copy(),
				tool: {
					messageID: tool.messageID,
					callID: tool.callID,
				},
			};
		}
		return {
			id: id,
			sessionID: input.sessionID,
			permission: input.permission,
			patterns: input.patterns.copy(),
			metadata: input.metadata,
			always: input.always.copy(),
		};
	}

	function nextPermissionID():String {
		final id = 'permission_${StringTools.lpad(Std.string(nextID), "0", 6)}';
		nextID += 1;
		return id;
	}

	function remove(id:String):Void {
		pending.remove(id);
		order.remove(id);
	}

	static function rejectError(reply:PermissionReply):Error {
		return reply.message == null ? new PermissionRejectedError() : new PermissionCorrectedError(reply.message);
	}

	static function resolvedVoid():Promise<Bool> {
		return Promise.resolve(true);
	}
}

/**
 * Directory-scoped owner for async permission services.
 *
 * Services are cached by `InstanceRuntime` directory and disposed when the
 * corresponding instance is disposed or reloaded, matching upstream pending
 * permission cleanup without requiring the full Effect layer yet.
 */
class PermissionAsyncRuntime {
	static final services:Map<String, PermissionAsyncService> = new Map();
	static var unsubscribe:Null<Void->Void> = null;

	public static function forContext(context:InstanceContext):PermissionAsyncService {
		ensureSubscribed();
		final key = context.directory;
		final existing = services.get(key);
		if (existing != null)
			return existing;
		final service = new PermissionAsyncService();
		services.set(key, service);
		return service;
	}

	public static function reset():Void {
		for (service in services) {
			service.dispose();
		}
		services.clear();
		if (unsubscribe != null) {
			unsubscribe();
			unsubscribe = null;
		}
	}

	static function ensureSubscribed():Void {
		if (unsubscribe != null)
			return;
		unsubscribe = InstanceRuntime.subscribe(event -> {
			final service = services.get(event.directory);
			if (service == null)
				return;
			services.remove(event.directory);
			service.dispose();
		});
	}
}
