package opencodehx.tool;

class TextDiff {
	public static function unified(path:String, oldContent:String, newContent:String):String {
		final output = ['--- ${path}', '+++ ${path}', "@@ -1 +1 @@"];
		final oldLines = splitLines(oldContent);
		final newLines = splitLines(newContent);
		final limit = oldLines.length > newLines.length ? oldLines.length : newLines.length;
		for (i in 0...limit) {
			final oldLine = i < oldLines.length ? oldLines[i] : null;
			final newLine = i < newLines.length ? newLines[i] : null;
			if (oldLine == newLine && oldLine != null) {
				output.push(' ${oldLine}');
			} else {
				if (oldLine != null)
					output.push('-${oldLine}');
				if (newLine != null)
					output.push('+${newLine}');
			}
		}
		return output.join("\n");
	}

	public static function countAdditions(oldContent:String, newContent:String):Int {
		return countChanged(oldContent, newContent, true);
	}

	public static function countDeletions(oldContent:String, newContent:String):Int {
		return countChanged(oldContent, newContent, false);
	}

	public static function splitLines(content:String):Array<String> {
		final normalized = StringTools.replace(content, "\r\n", "\n");
		final lines = normalized.split("\n");
		if (lines.length > 0 && lines[lines.length - 1] == "")
			lines.pop();
		return lines;
	}

	static function countChanged(oldContent:String, newContent:String, additions:Bool):Int {
		final oldLines = splitLines(oldContent);
		final newLines = splitLines(newContent);
		final limit = oldLines.length > newLines.length ? oldLines.length : newLines.length;
		var count = 0;
		for (i in 0...limit) {
			final oldLine = i < oldLines.length ? oldLines[i] : null;
			final newLine = i < newLines.length ? newLines[i] : null;
			if (oldLine != newLine) {
				if (additions && newLine != null)
					count++;
				if (!additions && oldLine != null)
					count++;
			}
		}
		return count;
	}
}
