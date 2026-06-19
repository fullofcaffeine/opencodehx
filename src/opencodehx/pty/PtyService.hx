package opencodehx.pty;

import haxe.DynamicAccess;
import js.lib.Error;
import opencodehx.bus.EventBus;
import opencodehx.externs.node.NodePty;
import opencodehx.externs.node.NodePty.PtyProcess;
import opencodehx.host.node.NodeProcess;
import opencodehx.pty.PtyTypes.PtyCreateInput;
import opencodehx.pty.PtyTypes.PtyEvent;
import opencodehx.pty.PtyTypes.PtyEventType;
import opencodehx.pty.PtyTypes.PtyID;
import opencodehx.pty.PtyTypes.PtyInfo;
import opencodehx.pty.PtyTypes.PtyStatus;
import opencodehx.pty.PtyTypes.PtyUpdateInput;

private typedef ActivePty = {
	final info:PtyInfo;
	final process:PtyProcess;
}

class PtyService {
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
		final session:ActivePty = {info: info, process: process};
		sessions.set(id.toString(), session);
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
}
