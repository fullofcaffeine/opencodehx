package opencodehx.cli;

typedef GitHubRemoteInfo = {
	final owner:String;
	final repo:String;
}

/**
 * Pure GitHub remote URL parser used by the GitHub CLI command.
 *
 * This mirrors upstream's accepted remote shapes without performing any git or
 * network side effects. The live GitHub action runner remains a later slice.
 */
class GitHubRemote {
	static final REMOTE = ~/^(?:(?:https?|ssh):\/\/)?(?:git@)?github\.com[:\/]([^\/]+)\/([^\/]+?)(?:\.git)?$/;

	public static function parse(url:String):Null<GitHubRemoteInfo> {
		if (!REMOTE.match(url))
			return null;
		return {
			owner: REMOTE.matched(1),
			repo: REMOTE.matched(2),
		};
	}
}
