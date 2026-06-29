package opencodehx.session;

/**
 * Tracks nearby instruction files already injected during one assistant
 * message. Upstream keeps the same lifecycle in `session/instruction.ts`: read
 * tools claim a reminder path while the assistant response is in progress, and
 * the session finalizer clears claims once that message is complete.
 */
class SessionInstructionClaims {
	final byMessage:Map<String, Array<String>>;

	public function new() {
		byMessage = new Map();
	}

	public function has(messageID:String, filepath:String):Bool {
		final paths = byMessage.get(messageID);
		return paths != null && paths.indexOf(filepath) != -1;
	}

	public function claim(messageID:String, filepath:String):Void {
		final paths = byMessage.get(messageID);
		if (paths == null) {
			byMessage.set(messageID, [filepath]);
			return;
		}
		if (paths.indexOf(filepath) == -1)
			paths.push(filepath);
	}

	public function clear(messageID:String):Void {
		byMessage.remove(messageID);
	}
}
