package opencodehx.util;

import js.lib.Promise;

class Lock {
	static final locks:Map<String, LockState> = [];

	public static function read(key:String):Promise<LockHandle> {
		final lock = get(key);
		return new Promise<LockHandle>((resolve, _) -> {
			final acquire = () -> {
				lock.readers++;
				resolve(new LockHandle(() -> {
					lock.readers--;
					process(key);
				}));
			}
			if (!lock.writer && lock.waitingWriters.length == 0)
				acquire();
			else
				lock.waitingReaders.push(acquire);
		});
	}

	public static function write(key:String):Promise<LockHandle> {
		final lock = get(key);
		return new Promise<LockHandle>((resolve, _) -> {
			final acquire = () -> {
				lock.writer = true;
				resolve(new LockHandle(() -> {
					lock.writer = false;
					process(key);
				}));
			}
			if (!lock.writer && lock.readers == 0)
				acquire();
			else
				lock.waitingWriters.push(acquire);
		});
	}

	static function get(key:String):LockState {
		var lock = locks.get(key);
		if (lock == null) {
			lock = new LockState();
			locks.set(key, lock);
		}
		return lock;
	}

	static function process(key:String):Void {
		final lock = locks.get(key);
		if (lock == null || lock.writer || lock.readers > 0)
			return;

		final nextWriter = lock.waitingWriters.shift();
		if (nextWriter != null) {
			nextWriter();
			return;
		}

		while (lock.waitingReaders.length > 0) {
			final nextReader = lock.waitingReaders.shift();
			if (nextReader != null)
				nextReader();
		}

		if (lock.readers == 0 && !lock.writer && lock.waitingReaders.length == 0 && lock.waitingWriters.length == 0)
			locks.remove(key);
	}
}

class LockHandle {
	final release:Void->Void;
	var released:Bool;

	public function new(release:Void->Void) {
		this.release = release;
		released = false;
	}

	public function dispose():Void {
		if (released)
			return;
		released = true;
		release();
	}
}

private typedef LockWake = Void->Void;

private class LockState {
	public var readers:Int = 0;
	public var writer:Bool = false;
	public final waitingReaders:Array<LockWake> = [];
	public final waitingWriters:Array<LockWake> = [];

	public function new() {}
}
