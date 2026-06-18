package opencodehx.session;

abstract MessageID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):MessageID {
		return new MessageID(value);
	}

	public inline function toString():String {
		return this;
	}
}
