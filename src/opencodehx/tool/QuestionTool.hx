package opencodehx.tool;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import js.lib.Promise;
import opencodehx.question.QuestionRuntime.QuestionAnswer;
import opencodehx.question.QuestionRuntime.QuestionInfo;
import opencodehx.question.QuestionRuntime.QuestionOption;
import opencodehx.question.QuestionRuntime.QuestionService;
import opencodehx.session.MessageID;
import opencodehx.session.SessionID;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolInputDecode;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolTypes.ToolResultMetadata;

typedef QuestionToolInput = {
	final questions:Array<QuestionInfo>;
}

typedef QuestionToolMetadata = {
	final messageID:MessageID;
	final callID:String;
}

/**
 * Async question tool facade over `QuestionRuntime`.
 *
 * The core registry is still synchronous, so this module owns the executable
 * wrapper behavior proved by upstream `tool/question.test.ts` until the final
 * registry/session runner can await async tools directly.
 */
class QuestionTool {
	public static inline final id = "question";

	public static function decode(raw:ToolCallInput):ToolInputDecode<QuestionToolInput> {
		final issues:Array<String> = [];
		final args = ToolValidation.record(raw.unknown(), issues);
		if (args == null)
			return Invalid(issues);
		final questionsArray = ToolValidation.requireArray(args, "questions", issues);
		final questions = questionsArray == null ? [] : decodeQuestions(questionsArray, issues);
		return ToolValidation.finish(issues, {questions: questions});
	}

	@:async
	public static function executeRaw(raw:ToolCallInput, ctx:ToolContext, service:QuestionService):Promise<ToolResult> {
		return switch decode(raw) {
			case Decoded(input):
				await(execute(input, ctx, service));
			case Invalid(issues):
				throw new ToolException(InvalidArguments(id, issues));
		}
	}

	@:async
	public static function execute(input:QuestionToolInput, ctx:ToolContext, service:QuestionService):Promise<ToolResult> {
		final answers = await(service.ask({
			sessionID: SessionID.make(requiredContext(ctx.sessionID, "sessionID")),
			questions: input.questions,
			tool: toolMetadata(ctx),
		}));
		return {
			title: title(input.questions.length),
			output: output(input.questions, answers),
			metadata: ToolResultMetadata.checked({answers: answers}),
		};
	}

	static function decodeQuestions(items:UnknownArray, issues:Array<String>):Array<QuestionInfo> {
		final out:Array<QuestionInfo> = [];
		for (index in 0...items.length) {
			final prefix = 'questions[${index}]';
			final record = recordAt(items, index, prefix, issues);
			if (record == null)
				continue;
			final question = stringField(record, "question", '${prefix}.question', issues);
			final header = stringField(record, "header", '${prefix}.header', issues);
			final optionsArray = arrayField(record, "options", '${prefix}.options', issues);
			final options = optionsArray == null ? [] : decodeOptions(optionsArray, '${prefix}.options', issues);
			final multiple = optionalBoolField(record, "multiple", '${prefix}.multiple', issues);
			final custom = optionalBoolField(record, "custom", '${prefix}.custom', issues);
			out.push({
				question: question,
				header: header,
				options: options,
				multiple: multiple,
				custom: custom,
			});
		}
		return out;
	}

	static function decodeOptions(items:UnknownArray, path:String, issues:Array<String>):Array<QuestionOption> {
		final out:Array<QuestionOption> = [];
		for (index in 0...items.length) {
			final prefix = '${path}[${index}]';
			final record = recordAt(items, index, prefix, issues);
			if (record == null)
				continue;
			out.push({
				label: stringField(record, "label", '${prefix}.label', issues),
				description: stringField(record, "description", '${prefix}.description', issues),
			});
		}
		return out;
	}

	static function recordAt(items:UnknownArray, index:Int, path:String, issues:Array<String>):Null<UnknownRecord> {
		final record = UnknownNarrow.record(items.get(index));
		if (record == null)
			issues.push('${path}: expected object');
		return record;
	}

	static function arrayField(record:UnknownRecord, field:String, path:String, issues:Array<String>):Null<UnknownArray> {
		if (!record.hasOwn(field) || absent(record.get(field))) {
			issues.push('${path}: expected array');
			return null;
		}
		final value = UnknownNarrow.array(record.get(field));
		if (value == null)
			issues.push('${path}: expected array');
		return value;
	}

	static function stringField(record:UnknownRecord, field:String, path:String, issues:Array<String>):String {
		if (!record.hasOwn(field) || absent(record.get(field))) {
			issues.push('${path}: expected string');
			return "";
		}
		final value = UnknownNarrow.string(record.get(field));
		if (value == null) {
			issues.push('${path}: expected string');
			return "";
		}
		return value;
	}

	static function optionalBoolField(record:UnknownRecord, field:String, path:String, issues:Array<String>):Null<Bool> {
		if (!record.hasOwn(field) || absent(record.get(field)))
			return null;
		final value = UnknownNarrow.bool(record.get(field));
		if (value == null)
			issues.push('${path}: expected boolean');
		return value;
	}

	static function toolMetadata(ctx:ToolContext):Null<QuestionToolMetadata> {
		if (ctx.callID == null || ctx.callID == "")
			return null;
		return {
			messageID: MessageID.make(requiredContext(ctx.messageID, "messageID")),
			callID: ctx.callID,
		};
	}

	static function requiredContext(value:Null<String>, name:String):String {
		if (value == null || value == "")
			throw new ToolException(ExecutionFailed(id, 'Missing tool context ${name}'));
		return value;
	}

	static function title(count:Int):String {
		return 'Asked ${count} question${count == 1 ? "" : "s"}';
	}

	static function output(questions:Array<QuestionInfo>, answers:Array<QuestionAnswer>):String {
		final formatted:Array<String> = [];
		for (index in 0...questions.length) {
			final answer = index < answers.length ? answers[index] : null;
			final text = answer == null || answer.length == 0 ? "Unanswered" : answer.join(", ");
			formatted.push('"${questions[index].question}"="${text}"');
		}
		return 'User has answered your questions: ${formatted.join(", ")}. You can now continue with the user\'s answers in mind.';
	}

	static function absent(value:Unknown):Bool {
		return UnknownNarrow.isUndefined(value) || UnknownNarrow.isNull(value);
	}
}
