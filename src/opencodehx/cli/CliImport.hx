package opencodehx.cli;

typedef ShareSession = {
	final id:String;
	@:optional final title:String;
}

typedef ShareMessage = {
	final id:String;
	final sessionID:String;
}

typedef SharePart = {
	final id:String;
	final messageID:String;
}

typedef ShareImportMessage = {
	final info:ShareMessage;
	final parts:Array<SharePart>;
}

typedef ShareImportData = {
	final info:ShareSession;
	final messages:Array<ShareImportMessage>;
}

enum ShareImportItem {
	Session(data:ShareSession);
	Message(data:ShareMessage);
	Part(data:SharePart);
	SessionDiff;
	Model;
}

private typedef ParsedOrigin = {
	final scheme:String;
	final host:String;
	final port:String;
}

/**
 * Pure helpers for the `import <file>` command.
 *
 * Fetch fallback, file IO, validation against full SDK schemas, and database
 * writes belong to the side-effecting import command slice; this module covers
 * the upstream helper behavior that can be proven without network or storage.
 */
class CliImport {
	static final SHARE_URL = ~/^https?:\/\/[^\/]+\/share\/([a-zA-Z0-9_-]+)$/;
	static final ORIGIN = ~/^(https?):\/\/([^\/:]+)(?::([0-9]+))?(?:\/|$)/;

	public static function parseShareUrl(url:String):Null<String> {
		return SHARE_URL.match(url) ? SHARE_URL.matched(1) : null;
	}

	public static function shouldAttachShareAuthHeaders(shareUrl:String, accountBaseUrl:String):Bool {
		final share = parseOrigin(shareUrl);
		final account = parseOrigin(accountBaseUrl);
		if (share == null || account == null)
			return false;
		return share.scheme == account.scheme && share.host == account.host && normalizePort(share) == normalizePort(account);
	}

	public static function transformShareData(items:Array<ShareImportItem>):Null<ShareImportData> {
		var session:Null<ShareSession> = null;
		final messages:Array<ShareMessage> = [];
		final partsByMessage = new Map<String, Array<SharePart>>();

		for (item in items) {
			switch item {
				case Session(data):
					if (session == null)
						session = data;
				case Message(data):
					messages.push(data);
				case Part(data):
					if (!partsByMessage.exists(data.messageID))
						partsByMessage.set(data.messageID, []);
					partsByMessage.get(data.messageID).push(data);
				case SessionDiff | Model:
			}
		}

		if (session == null || messages.length == 0)
			return null;

		final grouped:Array<ShareImportMessage> = [];
		for (message in messages) {
			final parts = partsByMessage.exists(message.id) ? partsByMessage.get(message.id) : [];
			grouped.push({info: message, parts: parts});
		}

		return {info: session, messages: grouped};
	}

	static function parseOrigin(url:String):Null<ParsedOrigin> {
		if (!ORIGIN.match(url))
			return null;
		return {
			scheme: ORIGIN.matched(1).toLowerCase(),
			host: ORIGIN.matched(2).toLowerCase(),
			port: ORIGIN.matched(3) == null ? "" : ORIGIN.matched(3),
		};
	}

	static function normalizePort(origin:ParsedOrigin):String {
		if (origin.port != "")
			return origin.port;
		return origin.scheme == "https" ? "443" : "80";
	}
}
