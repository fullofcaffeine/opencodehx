package opencodehx.smoke;

import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.session.SessionExport;
import opencodehx.session.SessionID;
import opencodehx.session.SessionProcessor;
import opencodehx.storage.SqliteSessionStore;

class SessionPersistenceSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-session-persist-"));
		final store = new SqliteSessionStore(NodePath.join(root, "opencodehx.db"));
		try {
			SessionProcessor.run({
				prompt: "Export me",
				directory: root,
				sessionID: "ses_export",
				projectID: "proj_export",
				store: store,
			});
			final sessionID = SessionID.make("ses_export");
			final exported = SessionExport.exportData(store, sessionID);
			eq(Reflect.field(exported.info, "id").toString(), "ses_export", "session export info id");
			eq(exported.messages.length, 2, "session export message count");
			eq(Reflect.field(Reflect.field(cast exported.messages[0], "info"), "role"), "user", "session export first role");
			final rawPart = cast(Reflect.field(cast exported.messages[0], "parts"), Array<Dynamic>)[0];
			eq(Reflect.field(rawPart, "text"), "Export me", "session export raw text");

			final sanitized = SessionExport.exportData(store, sessionID, true);
			eq(Reflect.field(sanitized.info, "title"), "[redacted:session-title:ses_export]", "session export sanitized title");
			final sanitizedPart = cast(Reflect.field(cast sanitized.messages[0], "parts"), Array<Dynamic>)[0];
			eq(Reflect.field(sanitizedPart, "text"), "[redacted:text:prt_user_text_ses_export]", "session export sanitized text");

			store.close();
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			store.close();
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
