package opencodehx.tool;

import genes.js.Async.await;
import js.lib.Promise;
import opencodehx.externs.web.GlobalFetch;
import opencodehx.host.node.NodeBuffer;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolInputDecode;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolTypes.ToolResultMetadata;

enum abstract WebFetchFormat(String) from String to String {
	var Text = "text";
	var Markdown = "markdown";
	var Html = "html";
}

typedef WebFetchInput = {
	final url:String;
	final format:WebFetchFormat;
}

/**
 * Async web fetch tool runtime for the upstream `tool/webfetch` behavior.
 *
 * The current core `ToolDef` surface is synchronous, so this module exposes the
 * executable webfetch behavior without registering it in the sync tool loop yet.
 * Once the session tool runner grows async execution, this can be wrapped as a
 * normal builtin tool without changing the body handling or attachment model.
 */
class WebFetchTool {
	public static function decode(raw:ToolCallInput):ToolInputDecode<WebFetchInput> {
		final issues:Array<String> = [];
		final args = ToolValidation.record(raw.unknown(), issues);
		if (args == null)
			return Invalid(issues);
		final url = ToolValidation.requireString(args, "url", issues);
		final rawFormat = ToolValidation.requireString(args, "format", issues);
		final format = parseFormat(rawFormat);
		if (format == null)
			issues.push("format: expected text, markdown, or html");
		return ToolValidation.finish(issues, {url: url, format: format == null ? WebFetchFormat.Text : format});
	}

	@:async
	public static function executeRaw(raw:ToolCallInput, ctx:ToolContext):Promise<ToolResult> {
		return switch decode(raw) {
			case Decoded(input):
				await(execute(input, ctx));
			case Invalid(issues):
				throw new ToolException(InvalidArguments("webfetch", issues));
		}
	}

	@:async
	public static function execute(input:WebFetchInput, _ctx:ToolContext):Promise<ToolResult> {
		final response = await(GlobalFetch.webFetchResponse(input.url));
		if (!response.ok)
			throw new ToolException(ExecutionFailed("webfetch", 'Fetch failed with HTTP ${response.status}'));

		final mime = mediaType(response.headers.get("content-type"));
		final formatText:String = input.format;
		if (isImageAttachment(mime)) {
			final bytes = await(response.arrayBuffer());
			final dataUrl = 'data:${mime};base64,${NodeBuffer.fromArrayBufferBase64(bytes)}';
			return {
				title: "Fetched image",
				output: "Image fetched successfully",
				metadata: ToolResultMetadata.checked({url: input.url, mime: mime, format: formatText}),
				attachments: [
					{
						type: "file",
						mime: mime,
						url: dataUrl
					}
				],
			};
		}

		final text = await(response.text());
		return {
			title: "Fetched URL",
			output: text,
			metadata: ToolResultMetadata.checked({url: input.url, mime: mime, format: formatText}),
		};
	}

	static function parseFormat(value:String):Null<WebFetchFormat> {
		return switch value {
			case "text":
				WebFetchFormat.Text;
			case "markdown":
				WebFetchFormat.Markdown;
			case "html":
				WebFetchFormat.Html;
			case _:
				null;
		}
	}

	static function mediaType(contentType:Null<String>):String {
		if (contentType == null || contentType == "")
			return "text/plain";
		return contentType.split(";")[0].toLowerCase();
	}

	static function isImageAttachment(mime:String):Bool {
		return StringTools.startsWith(mime, "image/") && mime != "image/svg+xml";
	}
}
