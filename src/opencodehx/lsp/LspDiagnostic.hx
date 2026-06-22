package opencodehx.lsp;

import opencodehx.lsp.LspTypes.LspDiagnosticInfo as DiagnosticInfo;

class LspDiagnostic {
	static final MAX_PER_FILE = 20;

	public static function pretty(diagnostic:DiagnosticInfo):String {
		final severity = switch diagnostic.severity {
			case 2: "WARN";
			case 3: "INFO";
			case 4: "HINT";
			case _: "ERROR";
		}
		final line = diagnostic.range.start.line + 1;
		final col = diagnostic.range.start.character + 1;
		return '${severity} [${line}:${col}] ${diagnostic.message}';
	}

	public static function report(file:String, issues:Array<DiagnosticInfo>):String {
		final errors:Array<DiagnosticInfo> = [];
		for (issue in issues) {
			if (issue.severity == 1)
				errors.push(issue);
		}
		if (errors.length == 0)
			return "";
		final lines:Array<String> = [];
		final limit = errors.length < MAX_PER_FILE ? errors.length : MAX_PER_FILE;
		for (index in 0...limit)
			lines.push(pretty(errors[index]));
		final more = errors.length - MAX_PER_FILE;
		final suffix = more > 0 ? '\n... and ${more} more' : "";
		return '<diagnostics file="${file}">\n${lines.join("\n")}${suffix}\n</diagnostics>';
	}
}
