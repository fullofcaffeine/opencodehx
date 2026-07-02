package opencodehx.tool;

import opencodehx.host.node.NodePath;
import opencodehx.lsp.LspDiagnostic;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolLspDiagnosticEntry;

class ToolLspReports {
	public static function collect(ctx:ToolContext, files:Array<String>):Array<ToolLspDiagnosticEntry> {
		final lsp = ctx.lsp;
		if (lsp == null)
			return [];
		for (file in files)
			lsp.touchFile(file, true);
		return lsp.diagnostics();
	}

	public static function appendWrite(output:String, file:String, diagnostics:Array<ToolLspDiagnosticEntry>):String {
		var next = output;
		var otherCount = 0;
		for (entry in diagnostics) {
			final current = sameFile(entry.file, file);
			if (!current && otherCount >= 5)
				continue;
			final block = LspDiagnostic.report(current ? file : entry.file, entry.issues);
			if (block == "")
				continue;
			if (current) {
				next += '\n\nLSP errors detected in this file, please fix:\n${block}';
				continue;
			}
			otherCount++;
			next += '\n\nLSP errors detected in other files:\n${block}';
		}
		return next;
	}

	public static function appendFile(output:String, file:String, diagnostics:Array<ToolLspDiagnosticEntry>):String {
		final block = LspDiagnostic.report(file, issuesFor(diagnostics, file));
		return block == "" ? output : output + '\n\nLSP errors detected in this file, please fix:\n${block}';
	}

	public static function appendPatch(output:String, files:Array<{file:String, label:String}>, diagnostics:Array<ToolLspDiagnosticEntry>):String {
		var next = output;
		for (file in files) {
			final block = LspDiagnostic.report(file.file, issuesFor(diagnostics, file.file));
			if (block != "")
				next += '\n\nLSP errors detected in ${file.label}, please fix:\n${block}';
		}
		return next;
	}

	static function issuesFor(diagnostics:Array<ToolLspDiagnosticEntry>, file:String) {
		for (entry in diagnostics) {
			if (sameFile(entry.file, file))
				return entry.issues;
		}
		return [];
	}

	static function sameFile(a:String, b:String):Bool {
		return NodePath.normalize(a) == NodePath.normalize(b);
	}
}
