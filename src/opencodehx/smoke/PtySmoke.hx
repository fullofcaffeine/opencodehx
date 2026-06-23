package opencodehx.smoke;

import genes.js.Async.await;
import genes.ts.Unknown;
import haxe.Json;
import js.lib.Error;
import js.lib.Uint8Array;
import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.web.WebStreams.WebTimers;
import opencodehx.host.Clock;
import opencodehx.host.node.NodeBuffer;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.pty.PtyService;
import opencodehx.pty.PtyTypes.PtyEvent;
import opencodehx.pty.PtyTypes.PtyID;
import opencodehx.pty.PtyTypes.PtySocketPayload;

class PtySmoke {
	@:async
	public static function run():Promise<Void> {
		shellSelectionParity();
		ptyShellArgsParity();

		if (NodeProcess.platform() == "win32")
			return;

		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-pty-"));
		final service = new PtyService(root);
		try {
			await(shortLivedLifecycle(service));
			await(removeLifecycle(service));
			await(outputReplay(service));
			await(reusedSocketIsolation(service));
			await(recycledSocketIsolation(service));
			await(inPlaceSocketDataMutation(service));
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

	static function shellSelectionParity():Void {
		eq(NodeProcess.shellNameForPlatform("/bin/bash", "linux"), "bash", "posix shell name");
		eq(NodeProcess.shellNameForPlatform("C:/tools/NU.EXE", "win32"), "nu", "windows shell name strips extension");
		eq(NodeProcess.shellNameForPlatform("C:/tools/PWSH.EXE", "win32"), "pwsh", "windows pwsh shell name");
		eq(NodeProcess.isLoginShellForPlatform("/bin/bash", "linux"), true, "bash is login shell");
		eq(NodeProcess.isLoginShellForPlatform("C:/tools/pwsh.exe", "win32"), false, "pwsh is not login shell");
		eq(NodeProcess.isPosixShellForPlatform("/bin/bash", "linux"), true, "bash is posix shell");
		eq(NodeProcess.isPosixShellForPlatform("/bin/fish", "linux"), false, "fish is not posix shell");
		eq(NodeProcess.isPosixShellForPlatform("C:/tools/pwsh.exe", "win32"), false, "pwsh is not posix shell");
		eq(NodeProcess.isPowerShellForPlatform("C:/tools/powershell.exe", "win32"), true, "powershell classification");
		eq(NodeProcess.windowsPathForPlatform("/cygdrive/c/Program Files/Git/bin/bash.exe", "win32"), "C:/Program Files/Git/bin/bash.exe",
			"cygdrive Git Bash path normalization");
		eq(NodeProcess.selectAcceptable({
			platform: "win32",
			shell: "NU.EXE",
			pwsh: "C:/Tools/pwsh.exe",
			powershell: "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe",
		}), "C:/Tools/pwsh.exe", "blacklisted Windows shell falls back to pwsh");
		eq(NodeProcess.selectPreferred({
			platform: "win32",
			shell: "/cygdrive/c/Program Files/Git/bin/bash.exe",
		}), "C:/Program Files/Git/bin/bash.exe",
			"preferred shell normalizes cygdrive Git Bash");
		eq(NodeProcess.selectAcceptable({
			platform: "win32",
			shell: "/usr/bin/bash",
			gitBash: "C:/Program Files/Git/bin/bash.exe",
		}), "C:/Program Files/Git/bin/bash.exe", "usr bin bash resolves to Git Bash");
		eq(NodeProcess.selectPreferred({
			platform: "win32",
			shell: "pwsh.exe",
			pwsh: "C:/Program Files/PowerShell/7/pwsh.exe",
		}), "C:/Program Files/PowerShell/7/pwsh.exe", "bare pwsh resolves to full path");
	}

	static function ptyShellArgsParity():Void {
		eq(PtyService.shellArgsForPlatform("C:/Program Files/PowerShell/7/pwsh.exe", [], "win32").join(","), "", "PowerShell PTY args");
		eq(PtyService.shellArgsForPlatform("C:/Program Files/Git/bin/bash.exe", [], "win32").join(","), "-l", "Git Bash PTY login args");
		eq(PtyService.shellArgsForPlatform("/bin/bash", ["--noprofile"], "linux").join(","), "--noprofile,-l", "existing args preserved before login arg");
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

	@:async
	static function outputReplay(service:PtyService):Promise<Void> {
		final info = service.create({command: "cat", title: "replay"});
		final first = new FakePtySocket(Unknown.fromBoundary({connection: "replay-first"}));
		final handler = service.connect(info.id, first);
		first.clear();
		service.write(info.id, "AAA\n");
		await(waitUntil(() -> first.text().indexOf("AAA") != -1, "pty replay first output"));
		final replay = new FakePtySocket(Unknown.fromBoundary({connection: "replay-second"}));
		service.connect(info.id, replay, 0);
		eq(replay.text().indexOf("AAA") != -1, true, "pty replays buffered output");
		final cursor = replay.cursor();
		eq(cursor > 0, true, "pty replay cursor");
		final tail = new FakePtySocket(Unknown.fromBoundary({connection: "replay-tail"}));
		service.connect(info.id, tail, -1);
		eq(tail.text().indexOf("AAA"), -1, "pty cursor -1 skips replay");
		eq(tail.cursor(), cursor, "pty tail cursor");
		if (handler != null)
			handler.onClose();
		service.remove(info.id);
	}

	@:async
	static function reusedSocketIsolation(service:PtyService):Promise<Void> {
		final a = service.create({command: "cat", title: "a"});
		final b = service.create({command: "cat", title: "b"});
		final socket = new FakePtySocket(Unknown.fromBoundary({connection: "a"}));
		service.connect(a.id, socket);
		socket.data = Unknown.fromBoundary({connection: "b"});
		socket.sink = [];
		service.connect(b.id, socket);
		socket.clear();
		service.write(a.id, "AAA\n");
		await(sleep(100));
		eq(socket.text().indexOf("AAA"), -1, "reused socket does not leak old pty output");
		service.remove(a.id);
		service.remove(b.id);
	}

	@:async
	static function recycledSocketIsolation(service:PtyService):Promise<Void> {
		final info = service.create({command: "cat", title: "recycled"});
		final socket = new FakePtySocket(Unknown.fromBoundary({connection: "a"}));
		service.connect(info.id, socket);
		socket.data = Unknown.fromBoundary({connection: "b"});
		socket.sink = [];
		service.write(info.id, "AAA\n");
		await(sleep(100));
		eq(socket.text().indexOf("AAA"), -1, "recycled socket object does not leak output");
		service.remove(info.id);
	}

	@:async
	static function inPlaceSocketDataMutation(service:PtyService):Promise<Void> {
		final info = service.create({command: "cat", title: "mutated"});
		final context = {connection: "a"};
		final socket = new FakePtySocket(Unknown.fromBoundary(context));
		service.connect(info.id, socket);
		socket.clear();
		context.connection = "b";
		service.write(info.id, "AAA\n");
		await(waitUntil(() -> socket.text().indexOf("AAA") != -1, "mutated socket data keeps connection"));
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

		return new Promise<Void>((resolve, reject) -> {
			// Haxe cannot call a `Promise<Void>` resolver directly because
			// `Void` has no value. Keep the resolver cast local to this smoke
			// harness; the timer and PTY lifecycle stay typed through externs.
			final resolveVoid:Void->Void = cast resolve;
			waitUntilTick(check, label, Clock.nowMillis() + timeout, resolveVoid, reject);
		});
	}

	static function waitUntilTick(check:Void->Bool, label:String, end:Float, resolve:Void->Void, reject:Dynamic->Void):Void {
		try {
			if (check()) {
				resolve();
				return;
			}
			if (Clock.nowMillis() > end) {
				reject(new Error('timeout waiting for $label'));
				return;
			}
			WebTimers.setTimeout(() -> waitUntilTick(check, label, end, resolve, reject), 25);
		} catch (error:Dynamic) {
			// Timer callbacks throw outside the Promise constructor's
			// synchronous executor. JS can throw arbitrary values here, so keep
			// the Dynamic catch at the smoke boundary and reject without letting
			// untyped values escape into product code.
			reject(error);
		}
	}

	static function sleep(ms:Int):Promise<Void> {
		return new Promise<Void>((resolve, _) -> {
			// See waitUntil: Promise<Void> needs a zero-arg resolver shape in
			// Haxe, while JS promises resolve with `undefined`.
			final resolveVoid:Void->Void = cast resolve;
			WebTimers.setTimeout(resolveVoid, ms);
		});
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}

private class FakePtySocket {
	public var readyState = 1;
	public var data:Unknown;
	public var sink:Array<String> = [];
	public var closed = 0;

	public function new(data:Unknown) {
		this.data = data;
	}

	public function send(data:PtySocketPayload):Void {
		sink.push(payloadText(data));
	}

	public function close(?code:Int, ?reason:String):Void {
		readyState = 3;
		closed += 1;
	}

	public function clear():Void {
		sink.resize(0);
	}

	public function text():String {
		return sink.join("");
	}

	public function cursor():Int {
		for (index in 0...sink.length) {
			final item = sink[sink.length - index - 1];
			if (item.length > 0 && item.charCodeAt(0) == 0) {
				final parsed:Dynamic = Json.parse(item.substr(1));
				return Std.int(Reflect.field(parsed, "cursor"));
			}
		}
		return -1;
	}

	static function payloadText(payload:PtySocketPayload):String {
		if (Std.isOfType(payload, String))
			return cast payload;
		// PtySocketPayload is an EitherType<String, Uint8Array>; after the String
		// branch is excluded, the cast is the typed-array branch used by the host
		// facade to decode bytes without raw Buffer syntax here.
		return NodeBuffer.fromBytesUtf8(cast(payload, Uint8Array));
	}
}
