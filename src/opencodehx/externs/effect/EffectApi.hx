package opencodehx.externs.effect;

@:jsRequire("effect", "Effect")
extern class EffectApi {
	static function succeed<T>(value:T):Dynamic;
	static function fail(error:Dynamic):Dynamic;
}
