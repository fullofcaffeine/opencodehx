package opencodehx.effect;

class RuntimeMemo<T> {
	final values:Array<T> = [];

	public function new() {}

	public function get(factory:Void->T):T {
		if (values.length == 0)
			values.push(factory());
		return values[0];
	}
}
