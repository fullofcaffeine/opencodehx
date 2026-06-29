package opencodehx.cli;

import opencodehx.session.MessageTypes.Part;

typedef GitHubPromptFile = {
	final filename:String;
	final content:String;
}

/**
	Pure helpers from the GitHub action command.

	The live GitHub action runner is a later side-effecting slice. These helpers
	are intentionally independent: one inspects typed message parts, the other
	formats deterministic context-limit diagnostics for attached prompt files.
**/
class GitHubAction {
	public static function extractResponseText(parts:Array<Part>):Null<String> {
		if (parts.length == 0)
			throw "no parts returned";
		var result:Null<String> = null;
		for (part in parts) {
			switch part {
				case TextPart(data):
					result = data.text;
				case _:
			}
		}
		return result;
	}

	public static function formatPromptTooLargeError(files:Array<GitHubPromptFile>):String {
		final message = "PROMPT_TOO_LARGE: The prompt exceeds the model's context limit.";
		if (files.length == 0)
			return message;
		final lines = [message, "", "Files in prompt:"];
		for (file in files)
			lines.push('- ${file.filename} (${base64OriginalKilobytes(file.content)} KB)');
		return lines.join("\n");
	}

	static function base64OriginalKilobytes(content:String):Int {
		return Math.round((content.length * 0.75) / 1024);
	}
}
