package opencodehx.smoke;

import opencodehx.share.ShareNextRuntime;
import opencodehx.share.ShareNextRuntime.ShareDiff;
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
					if (StringTools.endsWith(request.url, "/sync")) {
						{status: 200};
					} else {
						{
							status: 200,
							share: {
								id: "shr_abc",
								url: "https://legacy-share.example.com/share/abc",
								secret: "sec_123",
							},
						};
					}
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

		final firstDiff:Array<ShareDiff> = [
			{
				file: "a.ts",
				patch: "old",
				additions: 1,
				deletions: 1,
				status: "modified"
			},
		];
		final latestDiff:Array<ShareDiff> = [
			{
				file: "b.ts",
				patch: "new",
				additions: 2,
				deletions: 0,
				status: "modified"
			},
		];
		service.queueDiff("ses_1", firstDiff);
		service.queueDiff("ses_1", latestDiff);
		eq(service.flushSync("ses_1"), true, "share sync flushes queued diff");
		eq(calls.length, 2, "share sync request count");
		eq(calls[1].method, "POST", "share sync request method");
		eq(calls[1].url, "https://legacy-share.example.com/api/share/shr_abc/sync", "share sync request url");
		contains(calls[1].body, '"secret":"sec_123"', "share sync body secret");
		contains(calls[1].body, '"type":"session_diff"', "share sync body event type");
		contains(calls[1].body, '"file":"b.ts"', "share sync body latest diff");
		eq(calls[1].body.indexOf('"file":"a.ts"'), -1, "share sync body drops stale diff");
		eq(service.flushSync("ses_1"), false, "share sync without queued diff is false");
		eq(calls.length, 2, "share sync without queued diff does not call");

		eq(service.remove("ses_1"), true, "share remove returns true");
		eq(service.get("ses_1"), null, "share remove deletes row");
		eq(calls.length, 3, "share remove request count");
		eq(calls[2].method, "DELETE", "share remove request method");
		eq(calls[2].url, "https://legacy-share.example.com/api/share/shr_abc", "share remove request url");
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

	static function contains(text:String, expected:String, label:String):Void {
		if (text.indexOf(expected) == -1)
			throw '${label}: expected ${expected} in ${text}';
	}
}
