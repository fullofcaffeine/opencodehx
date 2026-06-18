package opencodehx.externs.node;

@:jsRequire("node:os")
extern class Os {
	static function tmpdir():String;
	static function homedir():String;
	static function userInfo():OsUserInfo;
}

typedef OsUserInfo = {
	final username:String;
}
