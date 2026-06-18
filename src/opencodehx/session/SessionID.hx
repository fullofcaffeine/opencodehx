package opencodehx.session;

abstract SessionID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):SessionID {
		return new SessionID(value);
	}

	public inline function toString():String {
		return this;
	}
}
