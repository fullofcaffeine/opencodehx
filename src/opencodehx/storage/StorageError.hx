package opencodehx.storage;

enum StorageFailure {
	NotFound(message:String);
	InvalidRow(source:String, issues:Array<String>);
}

class StorageException extends haxe.Exception {
	public final failure:StorageFailure;

	public function new(failure:StorageFailure) {
		this.failure = failure;
		super(format(failure));
	}

	static function format(failure:StorageFailure):String {
		return switch failure {
			case NotFound(message):
				'NotFoundError: ${message}';
			case InvalidRow(source, issues):
				'Invalid storage row in ${source}: ${issues.join("; ")}';
		}
	}
}
