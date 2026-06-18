package opencodehx.util;

class Lazy<T> {
	final load:() -> T;
	var loaded = false;
	var value:Null<T> = null;

	public function new(load:() -> T) {
		this.load = load;
	}

	public function get():T {
		if (!loaded) {
			value = load();
			loaded = true;
		}
		return value;
	}

	public function reset():Void {
		loaded = false;
		value = null;
	}
}
