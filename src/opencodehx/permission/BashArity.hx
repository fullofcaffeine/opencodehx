package opencodehx.permission;

class BashArity {
	static final ARITY:Array<{final command:String; final arity:Int;}> = [
		{command: "aws", arity: 3},
		{command: "consul kv", arity: 3},
		{command: "consul", arity: 2},
		{command: "docker compose", arity: 3},
		{command: "docker", arity: 2},
		{command: "git", arity: 2},
		{command: "npm run", arity: 3},
		{command: "npm", arity: 2},
		{command: "touch", arity: 1},
	];

	public static function prefix(tokens:Array<String>):Array<String> {
		var len = tokens.length;
		while (len > 0) {
			final candidate = tokens.slice(0, len).join(" ");
			final arity = arityFor(candidate);
			if (arity != null)
				return tokens.slice(0, arity);
			len--;
		}
		return tokens.length == 0 ? [] : tokens.slice(0, 1);
	}

	static function arityFor(command:String):Null<Int> {
		for (entry in ARITY) {
			if (entry.command == command)
				return entry.arity;
		}
		return null;
	}
}
