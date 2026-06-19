package opencodehx.externs.node;

@:jsRequire("node:crypto")
extern class Crypto {
	static function createHash(algorithm:String):CryptoHash;
}

extern class CryptoHash {
	function update(data:String):CryptoHash;
	function digest(encoding:String):String;
}
