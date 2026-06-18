package opencodehx.tool;

import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolPermissionRequest;

class ToolPermission {
	public static function require(id:String, ctx:ToolContext, request:ToolPermissionRequest):Void {
		final ask = ctx.ask;
		if (ask == null)
			return;
		final decision = ask(request);
		if (decision == null || decision.allowed)
			return;
		final reason = decision.reason == null ? request.patterns.join(", ") : decision.reason;
		throw new ToolException(PermissionDenied(id, reason));
	}
}
