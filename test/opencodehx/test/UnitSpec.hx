package opencodehx.test;

import genes.ts.Unknown;
import genes.ts.Imports;
import haxe.extern.EitherType;
import js.lib.Promise;

typedef UnitBody = Void->Void;
typedef AsyncUnitBody = Void->Promise<Void>;
typedef RunnerBody = EitherType<UnitBody, AsyncUnitBody>;
typedef DescribeFn = (name:String, body:UnitBody) -> Void;
typedef TestFn = (name:String, body:RunnerBody) -> Void;
typedef ExpectFn = (actual:Unknown) -> UnitExpectation;

typedef UnitExpectation = {
	function toBe<T>(expected:T):Void;
	function toEqual<T>(expected:T):Void;
	function toContain<T>(expected:T):Void;
	function toMatch(expected:String):Void;
};

/**
	Test runner `expect` deliberately accepts arbitrary observed values.

	The unsafety is contained at this runner facade boundary through
	`genes.ts.Unknown`; domain-specific assertion helpers should narrow values
	before they reach product code.
**/
/**
	Typed facade for Haxe-authored unit specs that generate native target-runner tests.

	The first target imports upstream-compatible `bun:test`; the facade keeps the
	Haxe spec stable while leaving room for Jest/Vitest import targets later.
**/
class UnitSpec {
	static final describeFn:DescribeFn = Imports.namedImport("bun:test", "describe", "describe");
	static final testFn:TestFn = Imports.namedImport("bun:test", "test", "test");
	static final expectFn:ExpectFn = Imports.namedImport("bun:test", "expect", "expect");

	public static inline function describe(name:String, body:UnitBody):Void {
		describeFn(name, body);
	}

	public static inline function test(name:String, body:UnitBody):Void {
		testFn(name, body);
	}

	public static inline function testAsync(name:String, body:AsyncUnitBody):Void {
		testFn(name, body);
	}

	public static inline function expect<T>(actual:T):UnitExpectation {
		return expectFn(Unknown.fromBoundary(actual));
	}
}
