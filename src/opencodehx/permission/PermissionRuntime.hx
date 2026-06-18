package opencodehx.permission;

import opencodehx.permission.PermissionTypes.PermissionAskRecord;
import opencodehx.permission.PermissionTypes.PermissionReply;
import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.permission.PermissionTypes.PermissionRuntimeDecision;
import opencodehx.permission.PermissionTypes.PermissionRuntimeOptions;
import opencodehx.tool.ToolTypes.ToolPermissionDecision;
import opencodehx.tool.ToolTypes.ToolPermissionRequest;

class PermissionRuntime {
	final ruleset:Array<PermissionRule>;
	final approved:Array<PermissionRule>;
	final prompt:Null<(PermissionAskRecord) -> PermissionReply>;
	final sessionID:String;
	final messageID:Null<String>;
	final callID:Null<String>;
	final pending:Array<PermissionAskRecord> = [];
	var nextID = 0;

	public function new(options:PermissionRuntimeOptions) {
		if (options.ruleset == null)
			ruleset = [];
		else
			ruleset = options.ruleset;
		if (options.approved == null)
			approved = [];
		else
			approved = options.approved;
		prompt = options.prompt;
		if (options.sessionID == null)
			sessionID = "";
		else
			sessionID = options.sessionID;
		messageID = options.messageID;
		callID = options.callID;
	}

	public function toToolAsk():ToolPermissionRequest->ToolPermissionDecision {
		return request -> {
			final decision = ask(request);
			return {
				allowed: decision.allowed,
				reason: decision.reason,
			};
		};
	}

	public function list():Array<PermissionAskRecord> {
		return pending.copy();
	}

	public function ask(input:ToolPermissionRequest):PermissionRuntimeDecision {
		var needsAsk = false;
		for (pattern in input.patterns) {
			final rule = PermissionRules.evaluate(input.permission, pattern, [ruleset, approved]);
			if (rule.action == "deny") {
				return {
					allowed: false,
					action: "deny",
					reason: 'The user has specified a rule which prevents this tool call: ${rule.permission} ${rule.pattern} deny'
				};
			}
			if (rule.action != "allow")
				needsAsk = true;
		}
		if (!needsAsk)
			return {allowed: true, action: "allow"};

		final record = makeRecord(input);
		pending.push(record);
		final fallback:PermissionReply = {reply: "reject"};
		final reply = prompt == null ? fallback : prompt(record);
		remove(record.id);
		if (reply.reply == "reject") {
			final message = reply.message == null ? "The user rejected permission to use this specific tool call." : reply.message;
			return {
				allowed: false,
				action: "ask",
				reason: message,
				request: record
			};
		}
		if (reply.reply == "always") {
			for (pattern in record.always) {
				approved.push({permission: record.permission, pattern: pattern, action: "allow"});
			}
		}
		return {allowed: true, action: "ask", request: record};
	}

	function makeRecord(input:ToolPermissionRequest):PermissionAskRecord {
		nextID++;
		final record:Dynamic = {
			id: "permission_" + StringTools.lpad(Std.string(nextID), "0", 6),
			sessionID: sessionID,
			permission: input.permission,
			patterns: input.patterns.copy(),
			metadata: input.metadata,
			always: input.always.copy(),
		};
		if (messageID != null && callID != null) {
			Reflect.setField(record, "tool", {messageID: messageID, callID: callID});
		}
		return cast record;
	}

	function remove(id:String):Void {
		var index = pending.length - 1;
		while (index >= 0) {
			if (pending[index].id == id)
				pending.splice(index, 1);
			index--;
		}
	}
}
