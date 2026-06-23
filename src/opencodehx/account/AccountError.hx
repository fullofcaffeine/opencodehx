package opencodehx.account;

typedef AccountTransportErrorInput = {
	final method:String;
	final url:String;
	@:optional final description:String;
}

class AccountTransportError extends haxe.Exception {
	public final _tag:String;
	public final method:String;
	public final url:String;
	public final description:Null<String>;

	public function new(input:AccountTransportErrorInput) {
		super(messageFor(input.method, input.url, input.description));
		_tag = "AccountTransportError";
		method = input.method;
		url = input.url;
		description = input.description;
	}

	static function messageFor(method:String, url:String, description:Null<String>):String {
		final lines = [
			'Could not reach ${method} ${url}.',
			"This failed before the server returned an HTTP response.",
		];
		if (description != null && description != "")
			lines.push(description);
		lines.push("Check your network, proxy, or VPN configuration and try again.");
		return lines.join("\n");
	}
}

class AccountServiceError extends haxe.Exception {
	@:keep
	public final _tag:String;

	public function new(message:String) {
		super(message);
		_tag = "AccountServiceError";
	}
}
