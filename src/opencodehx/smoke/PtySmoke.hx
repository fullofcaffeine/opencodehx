package opencodehx.smoke;

import genes.js.Async.await;
import js.Syntax;
import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.pty.PtyService;
import opencodehx.pty.PtyTypes.PtyEvent;
import opencodehx.pty.PtyTypes.PtyID;

class PtySmoke {
	@:async
	public static function run():Promise<Void> {
		if (NodeProcess.platform() == "win32")
			return;

		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-pty-"));
		final service = new PtyService(root);
		try {
			await(shortLivedLifecycle(service));
			await(removeLifecycle(service));
			bashLoginArgs(service);
			service.dispose();
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			// Smoke cleanup catches host PTY and timer failures, then rethrows so
			// the failing lifecycle assertion remains visible to the runner.
			service.dispose();
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	@:async
	static function shortLivedLifecycle(service:PtyService):Promise<Void> {
		final log:Array<PtyEvent> = [];
		final off = service.events.subscribe(event -> log.push(event));
		final info = service.create({
			command: "/usr/bin/env",
			args: ["sh", "-c", "sleep 0.1"],
			title: "sleep",
		});
		await(waitUntil(() -> types(log, info.id).indexOf("pty.deleted") != -1, "short-lived pty deleted"));
		eq(types(log, info.id).join(","), "pty.created,pty.exited,pty.deleted", "short-lived pty lifecycle");
		off();
	}

	@:async
	static function removeLifecycle(service:PtyService):Promise<Void> {
		final log:Array<PtyEvent> = [];
		final off = service.events.subscribe(event -> log.push(event));
		final info = service.create({command: "/bin/sh", title: "sh"});
		await(sleep(100));
		service.remove(info.id);
		await(waitUntil(() -> types(log, info.id).indexOf("pty.deleted") != -1, "removed pty deleted"));
		eq(types(log, info.id).join(","), "pty.created,pty.exited,pty.deleted", "removed pty lifecycle");
		off();
	}

	static function bashLoginArgs(service:PtyService):Void {
		if (!Fs.existsSync("/bin/bash"))
			return;
		final info = service.create({command: "/bin/bash", title: "bash"});
		eq(info.args.join(","), "-l", "bash login args");
		service.remove(info.id);
	}

	static function types(events:Array<PtyEvent>, id:PtyID):Array<String> {
		final out:Array<String> = [];
		for (event in events) {
			if (event.id.toString() == id.toString())
				out.push(event.type);
		}
		return out;
	}

	static function waitUntil(check:Void->Bool, label:String, ?timeoutMs:Int):Promise<Void> {
		var timeout = 5000;
		if (timeoutMs != null)
			timeout = timeoutMs;
		return Syntax.code("new Promise((resolve: (value: void) => void, reject: (reason?: Error) => void) => {
			const end = Date.now() + {2};
			const tick = () => {
				try {
					if ({0}()) {
						resolve(undefined);
						return;
					}
					if (Date.now() > end) {
						reject(new Error('timeout waiting for ' + {1}));
						return;
					}
					setTimeout(tick, 25);
				} catch (error) {
					reject(error instanceof Error ? error : new Error(String(error)));
				}
			};
			tick();
		})", check, label, timeout);
	}

	static function sleep(ms:Int):Promise<Void> {
		return Syntax.code("new Promise((resolve: (value: void) => void) => setTimeout(() => resolve(undefined), {0}))", ms);
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
