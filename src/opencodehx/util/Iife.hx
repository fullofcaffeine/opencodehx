package opencodehx.util;

class Iife {
	public static inline function iife<T>(fn:Void->T):T {
		return fn();
	}
}
