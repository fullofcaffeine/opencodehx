package opencodehx.smoke;

import opencodehx.share.ShareNextRuntime;
import opencodehx.share.ShareNextRuntime.ShareHttpRequest;
import opencodehx.share.ShareNextRuntime.ShareRequestHeaderName;
import opencodehx.share.ShareNextRuntime.ShareNextServiceRuntime;

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

		final calls:Array<ShareHttpRequest> = [];
		final service = new ShareNextServiceRuntime(legacy, request -> {
			calls.push(request);
			return switch request.method {
				case "POST":
					{
						status: 200,
						share: {
							id: "shr_abc",
							url: "https://legacy-share.example.com/share/abc",
							secret: "sec_123",
						},
					};
				case "DELETE":
					{status: 200};
				case other:
					throw 'unexpected share method ${other}';
			};
		});
		final created = service.create("ses_1");
		eq(created.id, "shr_abc", "share create id");
		eq(created.url, "https://legacy-share.example.com/share/abc", "share create url");
		eq(created.secret, "sec_123", "share create secret");
		eq(service.get("ses_1").id, "shr_abc", "share create persists row");
		eq(calls.length, 1, "share create request count");
		eq(calls[0].method, "POST", "share create request method");
		eq(calls[0].url, "https://legacy-share.example.com/api/share", "share create request url");

		eq(service.remove("ses_1"), true, "share remove returns true");
		eq(service.get("ses_1"), null, "share remove deletes row");
		eq(calls.length, 2, "share remove request count");
		eq(calls[1].method, "DELETE", "share remove request method");
		eq(calls[1].url, "https://legacy-share.example.com/api/share/shr_abc", "share remove request url");
		eq(service.remove("ses_1"), false, "share remove missing row is false");

		final failed = new ShareNextServiceRuntime(defaultLegacy, _ -> ({status: 500}));
		try {
			failed.create("ses_failed");
			throw "share failed create should reject";
		} catch (error:String) {
			eq(error, "Share create failed with status 500", "share create failure status");
		}
		eq(failed.get("ses_failed"), null, "share create failure does not persist");
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
