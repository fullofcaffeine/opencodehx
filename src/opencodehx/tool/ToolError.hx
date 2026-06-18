package opencodehx.tool;

enum ToolFailure {
	UnknownTool(id:String);
	DisabledTool(id:String);
	InvalidArguments(id:String, issues:Array<String>);
	ExecutionFailed(id:String, message:String);
}

class ToolException extends haxe.Exception {
	public final failure:ToolFailure;

	public function new(failure:ToolFailure) {
		this.failure = failure;
		super(format(failure));
	}

	static function format(failure:ToolFailure):String {
		return switch failure {
			case UnknownTool(id):
				'Unknown tool: ${id}';
			case DisabledTool(id):
				'Tool is disabled: ${id}';
			case InvalidArguments(id, issues):
				'The ${id} tool was called with invalid arguments: ${issues.join("; ")}.\nPlease rewrite the input so it satisfies the expected schema.';
			case ExecutionFailed(id, message):
				'The ${id} tool failed: ${message}';
		}
	}
}
