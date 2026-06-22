package opencodehx.pty;

import genes.ts.Unknown;
import haxe.DynamicAccess;
import haxe.Json;
import js.Syntax;
import js.lib.Error;
import js.lib.Uint8Array;
import opencodehx.bus.EventBus;
import opencodehx.externs.node.NodePty;
import opencodehx.externs.node.NodePty.PtyProcess;
import opencodehx.externs.web.WebStreams.WebTextDecoder;
import opencodehx.externs.web.WebStreams.WebTextEncoder;
import opencodehx.host.node.NodeProcess;
import opencodehx.pty.PtyTypes.PtyConnectHandler;
import opencodehx.pty.PtyTypes.PtyCreateInput;
import opencodehx.pty.PtyTypes.PtyEvent;
import opencodehx.pty.PtyTypes.PtyEventType;
import opencodehx.pty.PtyTypes.PtyID;
import opencodehx.pty.PtyTypes.PtyInfo;
import opencodehx.pty.PtyTypes.PtySocket;
import opencodehx.pty.PtyTypes.PtySocketMessage;
import opencodehx.pty.PtyTypes.PtyStatus;
import opencodehx.pty.PtyTypes.PtyUpdateInput;

private typedef PtySubscriber = {
	final key:Unknown;
	final socket:PtySocket;
}

private typedef ActivePty = {
	final info:PtyInfo;
	final process:PtyProcess;
	var buffer:String;
	var bufferCursor:Int;
	var cursor:Int;
	final subscribers:Array<PtySubscriber>;
}

class PtyService {
	static inline final BUFFER_LIMIT = 1024 * 1024 * 2;
	static inline final BUFFER_CHUNK = 64 * 1024;

	final directory:String;
	final sessions = new Map<String, ActivePty>();
	var nextID = 1;

	public final events = new EventBus<PtyEvent>();

	public function new(directory:String) {
		this.directory = directory;
	}

	public function list():Array<PtyInfo> {
		final out:Array<PtyInfo> = [];
		for (session in sessions)
			out.push(session.info);
		return out;
	}

	public function get(id:PtyID):Null<PtyInfo> {
		final session = sessions.get(id.toString());
		return session == null ? null : session.info;
	}

	public function create(input:PtyCreateInput):PtyInfo {
		final id = PtyID.make("pty_" + StringTools.lpad(Std.string(nextID++), "0", 6));
		var command = NodeProcess.preferredShell();
		if (input.command != null && input.command != "")
			command = input.command;
		var args:Array<String> = [];
		final inputArgs = input.args;
		if (inputArgs != null)
			args = inputArgs.copy();
		if (NodeProcess.isLoginShell(command))
			args.push("-l");
		var cwd = directory;
		if (input.cwd != null && input.cwd != "")
			cwd = input.cwd;
		var title = "Terminal " + id.toString().substr(id.toString().length - 4);
		if (input.title != null && input.title != "")
			title = input.title;
		final env = ptyEnv(input.env);
		final process = NodePty.spawn(command, args, {
			name: "xterm-256color",
			cwd: cwd,
			env: env,
		});
		final info:PtyInfo = {
			id: id,
			title: title,
			command: command,
			args: args,
			cwd: cwd,
			status: PtyStatus.Running,
			pid: process.pid,
		};
		final session:ActivePty = {
			info: info,
			process: process,
			buffer: "",
			bufferCursor: 0,
			cursor: 0,
			subscribers: [],
		};
		sessions.set(id.toString(), session);
		process.onData(chunk -> {
			session.cursor += chunk.length;
			var index = 0;
			while (index < session.subscribers.length) {
				final subscriber = session.subscribers[index];
				if (subscriber.socket.readyState != 1 || !sameSocketKey(socketKey(subscriber.socket), subscriber.key)) {
					session.subscribers.splice(index, 1);
					continue;
				}
				try {
					subscriber.socket.send(chunk);
					index += 1;
				} catch (_:Error) {
					session.subscribers.splice(index, 1);
				}
			}
			session.buffer += chunk;
			if (session.buffer.length > BUFFER_LIMIT) {
				final excess = session.buffer.length - BUFFER_LIMIT;
				session.buffer = session.buffer.substr(excess);
				session.bufferCursor += excess;
			}
		});
		process.onExit(exit -> {
			if (info.status == PtyStatus.Exited)
				return;
			info.status = PtyStatus.Exited;
			events.publish({type: PtyEventType.Exited, id: id, exitCode: exit.exitCode});
			remove(id);
		});
		events.publish({type: PtyEventType.Created, id: id, info: info});
		return info;
	}

	public function update(id:PtyID, input:PtyUpdateInput):Null<PtyInfo> {
		final session = sessions.get(id.toString());
		if (session == null)
			return null;
		if (input.title != null && input.title != "")
			session.info.title = input.title;
		if (input.size != null)
			session.process.resize(input.size.cols, input.size.rows);
		events.publish({type: PtyEventType.Updated, id: id, info: session.info});
		return session.info;
	}

	public function resize(id:PtyID, cols:Int, rows:Int):Void {
		final session = sessions.get(id.toString());
		if (session != null && session.info.status == PtyStatus.Running)
			session.process.resize(cols, rows);
	}

	public function write(id:PtyID, data:String):Void {
		final session = sessions.get(id.toString());
		if (session != null && session.info.status == PtyStatus.Running)
			session.process.write(data);
	}

	public function connect(id:PtyID, socket:PtySocket, ?cursor:Int):Null<PtyConnectHandler> {
		final session = sessions.get(id.toString());
		if (session == null) {
			closeSocket(socket);
			return null;
		}
		final key = socketKey(socket);
		removeSubscriber(session, key);
		session.subscribers.push({key: key, socket: socket});
		if (!sendReplay(session, socket, key, cursor)) {
			closeSocket(socket);
			return null;
		}
		return {
			onMessage: message -> {
				if (session.info.status == PtyStatus.Running)
					session.process.write(socketMessageText(message));
			},
			onClose: () -> removeSubscriber(session, key),
		};
	}

	public function remove(id:PtyID):Void {
		final key = id.toString();
		final session = sessions.get(key);
		if (session == null)
			return;
		sessions.remove(key);
		if (session.info.status == PtyStatus.Running) {
			session.info.status = PtyStatus.Exited;
			events.publish({type: PtyEventType.Exited, id: id, exitCode: 0});
		}
		try {
			session.process.kill();
		} catch (_:Error) {
			// The PTY process may have already exited; lifecycle state above is
			// authoritative, so kill failures stay contained to teardown.
		}
		closeSubscribers(session);
		events.publish({type: PtyEventType.Deleted, id: id});
	}

	public function dispose():Void {
		final ids:Array<PtyID> = [];
		for (session in sessions)
			ids.push(session.info.id);
		for (id in ids)
			remove(id);
	}

	static function ptyEnv(extra:Null<DynamicAccess<String>>):DynamicAccess<String> {
		final env = NodeProcess.env();
		if (extra != null) {
			for (key in extra.keys()) {
				final value = extra.get(key);
				if (value != null)
					env.set(key, value);
			}
		}
		env.set("TERM", "xterm-256color");
		env.set("OPENCODE_TERMINAL", "1");
		if (NodeProcess.platform() == "win32") {
			env.set("LC_ALL", "C.UTF-8");
			env.set("LC_CTYPE", "C.UTF-8");
			env.set("LANG", "C.UTF-8");
		}
		return env;
	}

	static function sendReplay(session:ActivePty, socket:PtySocket, key:Unknown, ?cursor:Int):Bool {
		final start = session.bufferCursor;
		final end = session.cursor;
		var from = 0;
		if (cursor != null)
			from = cursor == -1 ? end : Std.int(Math.max(0, cursor));
		final data = if (session.buffer == "" || from >= end) {
			"";
		} else {
			final offset = Std.int(Math.max(0, from - start));
			offset >= session.buffer.length ? "" : session.buffer.substr(offset);
		}
		try {
			if (data != "") {
				var index = 0;
				while (index < data.length) {
					socket.send(data.substr(index, BUFFER_CHUNK));
					index += BUFFER_CHUNK;
				}
			}
			socket.send(cursorFrame(end));
			return true;
		} catch (_:Error) {
			removeSubscriber(session, key);
			return false;
		}
	}

	static function removeSubscriber(session:ActivePty, key:Unknown):Void {
		var index = session.subscribers.length - 1;
		while (index >= 0) {
			if (sameSocketKey(session.subscribers[index].key, key))
				session.subscribers.splice(index, 1);
			index -= 1;
		}
	}

	static function closeSubscribers(session:ActivePty):Void {
		for (subscriber in session.subscribers) {
			if (sameSocketKey(socketKey(subscriber.socket), subscriber.key))
				closeSocket(subscriber.socket);
		}
		session.subscribers.resize(0);
	}

	static function closeSocket(socket:PtySocket):Void {
		try {
			socket.close();
		} catch (_:Error) {}
	}

	static function socketKey(socket:PtySocket):Unknown {
		// Upstream keys PTY subscribers by `ws.data` when it is an object,
		// otherwise by the socket wrapper itself. Haxe has no object-identity
		// type for arbitrary JS host objects, so this boundary stays as
		// `unknown` and is only compared with strict JS identity below.
		return Syntax.code("({0}.data && typeof {0}.data === 'object' ? {0}.data : {0})", socket);
	}

	static function sameSocketKey(left:Unknown, right:Unknown):Bool {
		return Syntax.code("{0} === {1}", left, right);
	}

	static function cursorFrame(cursor:Int):Uint8Array {
		final bytes = new WebTextEncoder().encode(Json.stringify({cursor: cursor}));
		final out = new Uint8Array(bytes.length + 1);
		out[0] = 0;
		out.set(bytes, 1);
		return out;
	}

	static function socketMessageText(message:PtySocketMessage):String {
		if (Std.isOfType(message, String))
			return cast message;
		// PtySocketMessage is EitherType<String, ArrayBuffer>; after the String
		// branch is excluded, create a Uint8Array view for TextDecoder.
		return new WebTextDecoder().decode(new Uint8Array(cast message));
	}
}
