package opencodehx.server;

import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import opencodehx.server.ServerProtocol.DecodeResult;

typedef QuestionReplyRequest = {
	final answers:Array<Array<String>>;
}

/**
 * Decodes the upstream question reply route payload.
 *
 * This lives outside `ServerProtocol` because that module owns compile-time
 * macros for checked event names. Keeping `UnknownNarrow` here avoids pulling
 * JS-only narrowing helpers into macro context.
 */
class ServerQuestionProtocol {
	public static function decodeReply(raw:Unknown):DecodeResult<QuestionReplyRequest> {
		final record = UnknownNarrow.record(raw);
		if (record == null)
			return Rejected("answers: expected array");
		final answers = record.hasOwn("answers") ? UnknownNarrow.array(record.get("answers")) : null;
		if (answers == null)
			return Rejected("answers: expected array");
		final decoded = decodeAnswers(answers);
		if (decoded == null)
			return Rejected("answers: expected array of string arrays");
		return Decoded({answers: decoded});
	}

	static function decodeAnswers(raw:UnknownArray):Null<Array<Array<String>>> {
		final out:Array<Array<String>> = [];
		for (index in 0...raw.length) {
			final answer = UnknownNarrow.array(raw.get(index));
			if (answer == null)
				return null;
			final decoded:Array<String> = [];
			for (answerIndex in 0...answer.length) {
				final label = UnknownNarrow.string(answer.get(answerIndex));
				if (label == null)
					return null;
				decoded.push(label);
			}
			out.push(decoded);
		}
		return out;
	}
}
