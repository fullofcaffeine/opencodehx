package opencodehx.server;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import opencodehx.permission.PermissionTypes.PermissionReply;
import opencodehx.server.ServerProtocol.DecodeResult;

typedef PermissionReplyRequest = {
	final reply:PermissionReply;
}

/**
 * Decodes the upstream permission reply route payload.
 *
 * This lives outside `ServerProtocol` because that module owns compile-time
 * macros for checked event names. Keeping `UnknownNarrow` here avoids pulling
 * JS-only narrowing helpers into macro context.
 */
class ServerPermissionProtocol {
	public static function decodeReply(raw:Unknown):DecodeResult<PermissionReplyRequest> {
		final record = UnknownNarrow.record(raw);
		if (record == null)
			return Rejected("reply: expected string");
		final reply = record.hasOwn("reply") ? UnknownNarrow.string(record.get("reply")) : null;
		if (reply == null)
			return Rejected("reply: expected string");
		if (record.hasOwn("message")) {
			final message = UnknownNarrow.string(record.get("message"));
			if (message == null)
				return Rejected("message: expected string");
			return Decoded({reply: {reply: reply, message: message}});
		}
		return Decoded({reply: {reply: reply}});
	}
}
