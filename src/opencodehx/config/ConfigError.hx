package opencodehx.config;

enum ConfigFailure {
	JsonError(path:String, message:String);
	InvalidError(path:String, issues:Array<String>);
	IoError(path:String, message:String);
}

class ConfigException extends haxe.Exception {
	public final failure:ConfigFailure;

	public function new(failure:ConfigFailure) {
		this.failure = failure;
		super(ConfigFailureTools.message(failure));
	}
}

class ConfigFailureTools {
	public static function message(failure:ConfigFailure):String {
		return switch failure {
			case JsonError(path, message): 'ConfigJsonError: ${path}: ${message}';
			case InvalidError(path, issues): 'ConfigInvalidError: ${path}: ${issues.join("; ")}';
			case IoError(path, message): 'ConfigIoError: ${path}: ${message}';
		}
	}
}
