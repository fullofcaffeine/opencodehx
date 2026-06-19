package opencodehx.provider.copilot;

import genes.js.Async.await;
import js.html.Response;
import js.lib.Promise;
import js.lib.Uint8Array;
import opencodehx.externs.web.WebStreams.WebReadableStreamDefaultReader;
import opencodehx.externs.web.WebStreams.WebResponseStreams;
import opencodehx.externs.web.WebStreams.WebTextDecoder;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatRawStreamChunk;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamEvent;

class CopilotChatStreamAdapter {
	@:async
	public static function responseText(response:Response):Promise<String> {
		final body = WebResponseStreams.body(response);
		if (body == null)
			return "";
		return @:await readBody(body.getReader());
	}

	@:async
	public static function responseChunks(response:Response):Promise<Array<CopilotChatRawStreamChunk>> {
		final text = @:await responseText(response);
		return CopilotChatSseDecoder.decodeText(text);
	}

	@:async
	public static function responseEvents(response:Response, includeRawChunks:Bool, ?warnings:Array<String>):Promise<Array<CopilotChatStreamEvent>> {
		final chunks = @:await responseChunks(response);
		return CopilotChatStream.collectRaw(chunks, includeRawChunks, warnings);
	}

	@:async
	static function readBody(reader:WebReadableStreamDefaultReader<Uint8Array>):Promise<String> {
		final decoder = new WebTextDecoder();
		final out = new StringBuf();
		try {
			while (true) {
				final result = @:await reader.read();
				if (result.done)
					break;
				if (result.value != null)
					out.add(decoder.decode(result.value, {stream: true}));
			}
		} catch (error:haxe.Exception) {
			@:await reader.cancel();
			throw error;
		}
		out.add(decoder.decode());
		return out.toString();
	}
}
