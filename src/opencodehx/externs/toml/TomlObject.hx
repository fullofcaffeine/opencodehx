package opencodehx.externs.toml;

import genes.ts.Unknown;
import haxe.DynamicAccess;

typedef TomlValue = Unknown;

abstract TomlObject(DynamicAccess<TomlValue>) from DynamicAccess<TomlValue> to DynamicAccess<TomlValue> {
	public inline function get(field:String):Null<TomlValue> {
		return this.get(field);
	}

	public inline function set(field:String, value:TomlValue):Void {
		this.set(field, value);
	}

	public inline function remove(field:String):Bool {
		return this.remove(field);
	}
}
