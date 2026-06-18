package opencodehx.session;

enum MessageFailure {
	InvalidMessage(source:String, issues:Array<String>);
}

class MessageException extends haxe.Exception {
	public final failure:MessageFailure;

	public function new(failure:MessageFailure) {
		this.failure = failure;
		super(format(failure));
	}

	static function format(failure:MessageFailure):String {
		return switch failure {
			case InvalidMessage(source, issues):
				'Invalid message DTO in ${source}: ${issues.join("; ")}';
		}
	}
}
