package opencodehx.session;

abstract PartID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):PartID {
		return new PartID(value);
	}

	public inline function toString():String {
		return this;
	}
}
