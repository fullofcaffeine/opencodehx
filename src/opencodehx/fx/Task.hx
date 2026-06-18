package opencodehx.fx;

import opencodehx.externs.effect.EffectApi;

class Task<T> {
	final effect:Dynamic;

	function new(effect:Dynamic) {
		this.effect = effect;
	}

	public static function succeed<T>(value:T):Task<T> {
		return new Task(EffectApi.succeed(value));
	}

	public function toEffect():Dynamic {
		return effect;
	}
}
