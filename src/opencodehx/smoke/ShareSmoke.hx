package opencodehx.smoke;

import opencodehx.share.ShareNextRuntime;
import opencodehx.share.ShareNextRuntime.ShareRequestHeaderName;

class ShareSmoke {
	public static function run():Void {
		final legacy = ShareNextRuntime.request({enterpriseUrl: "https://legacy-share.example.com/"});
		eq(legacy.baseUrl, "https://legacy-share.example.com", "share legacy base url");
		eq(legacy.api.create, "/api/share", "share legacy create path");
		eq(legacy.api.sync("shr_123"), "/api/share/shr_123/sync", "share legacy sync path");
		eq(legacy.api.remove("shr_123"), "/api/share/shr_123", "share legacy remove path");
		eq(legacy.api.data("shr_123"), "/api/share/shr_123/data", "share legacy data path");
		eq(legacy.headers.length, 0, "share legacy headers");

		final defaultLegacy = ShareNextRuntime.request({});
		eq(defaultLegacy.baseUrl, ShareNextRuntime.DEFAULT_BASE_URL, "share default base url");
		eq(defaultLegacy.api.create, "/api/share", "share default create path");

		final org = ShareNextRuntime.request({
			activeAccount: {
				id: "acct-1",
				url: "https://control.example.com/",
				token: "st_test_token",
				activeOrgID: "org-1",
			}
		});
		eq(org.baseUrl, "https://control.example.com", "share org base url");
		eq(org.api.create, "/api/shares", "share org create path");
		eq(org.api.sync("shr_123"), "/api/shares/shr_123/sync", "share org sync path");
		eq(org.api.remove("shr_123"), "/api/shares/shr_123", "share org remove path");
		eq(org.api.data("shr_123"), "/api/shares/shr_123/data", "share org data path");
		eq(ShareNextRuntime.header(org, ShareRequestHeaderName.Authorization), "Bearer st_test_token", "share org authorization header");
		eq(ShareNextRuntime.header(org, ShareRequestHeaderName.OrgID), "org-1", "share org id header");

		try {
			ShareNextRuntime.request({
				activeAccount: {
					id: "acct-1",
					url: "https://control.example.com",
					activeOrgID: "org-1",
				}
			});
			throw "share missing token should fail";
		} catch (error:String) {
			eq(error, "No active account token available for sharing", "share missing token failure");
		}
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
