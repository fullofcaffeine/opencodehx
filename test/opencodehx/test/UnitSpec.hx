package opencodehx.test;

import genes.ts.Imports;
import haxe.extern.EitherType;
import js.lib.Promise;

typedef UnitBody = Void->Void;
typedef AsyncUnitBody = Void->Promise<Void>;
typedef RunnerBody = EitherType<UnitBody, AsyncUnitBody>;
typedef DescribeFn = (name:String, body:UnitBody) -> Void;
typedef TestFn = (name:String, body:RunnerBody) -> Void;
typedef ExpectFn = (actual:AssertionValue) -> UnitExpectation;

typedef UnitExpectation = {
	function toBe(expected:AssertionValue):Void;
	function toEqual(expected:AssertionValue):Void;
	function toContain(expected:AssertionValue):Void;
	function toMatch(expected:String):Void;
};

/**
	Test runner `expect` deliberately accepts arbitrary observed values.

	The unsafety is contained at this runner facade boundary and emitted as
	TypeScript `unknown`; domain-specific assertion helpers should narrow values
	before they reach product code.
**/
@:ts.type("unknown")
abstract AssertionValue(Dynamic) from Dynamic to Dynamic {}

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

	public static inline function expect(actual:AssertionValue):UnitExpectation {
		return expectFn(actual);
	}
}
