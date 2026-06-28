package opencodehx.cli;

typedef AccountDisplayAccount = {
	final email:String;
	final url:String;
}

typedef AccountDisplayOrg = {
	final id:String;
	final name:String;
}

/**
 * Pure display helpers for console account rows.
 *
 * The ANSI constants mirror upstream `cli/ui.ts`; side-effecting account
 * service/login flows remain outside this formatting helper.
 */
class AccountDisplay {
	public static inline final TEXT_HIGHLIGHT_BOLD = "\x1b[96m\x1b[1m";
	public static inline final TEXT_DIM = "\x1b[90m";
	public static inline final TEXT_NORMAL = "\x1b[0m";
	public static inline final TEXT_SUCCESS = "\x1b[92m";

	public static function formatAccountLabel(account:AccountDisplayAccount, isActive:Bool):String {
		return account.email + " " + dim(account.url) + activeSuffix(isActive);
	}

	public static function formatOrgLine(account:AccountDisplayAccount, org:AccountDisplayOrg, isActive:Bool):String {
		final dot = isActive ? TEXT_SUCCESS + "\u25cf" + TEXT_NORMAL : " ";
		final name = isActive ? TEXT_HIGHLIGHT_BOLD + org.name + TEXT_NORMAL : org.name;
		return "  " + dot + " " + name + "  " + dim(account.email) + "  " + dim(account.url) + "  " + dim(org.id);
	}

	static function dim(value:String):String {
		return TEXT_DIM + value + TEXT_NORMAL;
	}

	static function activeSuffix(isActive:Bool):String {
		return isActive ? dim(" (active)") : "";
	}
}
