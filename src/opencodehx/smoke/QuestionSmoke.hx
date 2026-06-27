package opencodehx.smoke;

import genes.js.Async.await;
import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.project.InstanceRuntime;
import opencodehx.project.InstanceRuntime.InstanceContext;
import opencodehx.project.InstanceRuntime.InstanceServiceID;
import opencodehx.project.ProjectRuntime;
import opencodehx.question.QuestionRuntime;
import opencodehx.question.QuestionRuntime.QuestionAnswer;
import opencodehx.question.QuestionRuntime.QuestionID;
import opencodehx.question.QuestionRuntime.QuestionInfo;
import opencodehx.question.QuestionRuntime.QuestionRejectedError;
import opencodehx.question.QuestionRuntime.QuestionRequest;
import opencodehx.question.QuestionRuntime.QuestionService;
import opencodehx.question.QuestionRuntime.QuestionTool;
import opencodehx.session.MessageID;
import opencodehx.session.SessionID;

class QuestionSmoke {
	@:async
	public static function run():Promise<Void> {
		ProjectRuntime.reset();
		InstanceRuntime.reset();
		QuestionRuntime.reset();
		await(askListReplyReject());
		await(multipleRequestsAndDirectoryIsolation());
		await(instanceDisposalRejectsPending());
		QuestionRuntime.reset();
		InstanceRuntime.reset();
		ProjectRuntime.reset();
	}

	@:async
	static function askListReplyReject():Promise<Void> {
		final context = bootTempContext("question-basic");
		final service = QuestionRuntime.forContext(context);
		final questions = singleQuestion("What would you like to do?", "Action", "Option 1", "Option 2");
		final tool:QuestionTool = {messageID: MessageID.make("msg_question"), callID: "call_question"};
		final promise = service.ask({sessionID: SessionID.make("ses_test"), questions: questions, tool: tool});

		final pending = await(service.list());
		eq(pending.length, 1, "question pending count");
		eq(pending[0].sessionID.toString(), "ses_test", "question pending session");
		eq(pending[0].questions[0].question, "What would you like to do?", "question pending text");
		eq(requireTool(pending[0]).callID, "call_question", "question pending tool call");

		await(service.reply({requestID: pending[0].id, answers: [["Option 1"]]}));
		eq(answerText(await(promise)), "Option 1", "question reply answer");
		eq((await(service.list())).length, 0, "question reply removes pending");

		await(service.reply({requestID: QuestionID.make("que_unknown"), answers: [["Missing"]]}));
		await(service.reject(QuestionID.make("que_unknown")));

		final rejected = service.ask({sessionID: SessionID.make("ses_reject"), questions: questions});
		final rejectedPending = await(service.list());
		await(service.reject(rejectedPending[0].id));
		eq(await(rejectionKind(rejected)), "rejected", "question reject promise");
		eq((await(service.list())).length, 0, "question reject removes pending");

		InstanceRuntime.dispose(context.directory);
	}

	@:async
	static function multipleRequestsAndDirectoryIsolation():Promise<Void> {
		final one = bootTempContext("question-one");
		final two = bootTempContext("question-two");
		final serviceOne = QuestionRuntime.forContext(one);
		final serviceTwo = QuestionRuntime.forContext(two);

		final first = serviceOne.ask({
			sessionID: SessionID.make("ses_one"),
			questions: [
				question("Question 1?", "Q1", ["A"]),
				question("Which environment?", "Env", ["Dev", "Prod"]),
			],
		});
		final second = serviceOne.ask({sessionID: SessionID.make("ses_two"), questions: [question("Question 2?", "Q2", ["B"])]});
		final isolated = serviceTwo.ask({sessionID: SessionID.make("ses_other"), questions: [question("Other?", "Other", ["C"])]});

		final onePending = await(serviceOne.list());
		final twoPending = await(serviceTwo.list());
		eq(onePending.length, 2, "question multiple pending count");
		eq(twoPending.length, 1, "question isolated pending count");
		eq(twoPending[0].sessionID.toString(), "ses_other", "question isolated session");

		await(serviceOne.reply({requestID: onePending[0].id, answers: [["A"], ["Dev"]]}));
		eq(answerText(await(first)), "A|Dev", "question multiple answers");
		await(serviceOne.reject(onePending[1].id));
		await(serviceTwo.reject(twoPending[0].id));
		eq(await(rejectionKind(second)), "rejected", "question second rejected");
		eq(await(rejectionKind(isolated)), "rejected", "question isolated rejected");
		InstanceRuntime.dispose(one.directory);
		InstanceRuntime.dispose(two.directory);
	}

	@:async
	static function instanceDisposalRejectsPending():Promise<Void> {
		final disposed = bootTempContext("question-dispose");
		final disposeService = QuestionRuntime.forContext(disposed);
		final disposePromise = disposeService.ask({sessionID: SessionID.make("ses_dispose"), questions: [question("Dispose?", "Dispose", ["Yes"])]});
		eq((await(disposeService.list())).length, 1, "question dispose pending count");
		InstanceRuntime.dispose(disposed.directory);
		eq(await(rejectionKind(disposePromise)), "rejected", "question dispose rejects");

		final reloaded = bootTempContext("question-reload");
		final reloadService = QuestionRuntime.forContext(reloaded);
		final reloadPromise = reloadService.ask({sessionID: SessionID.make("ses_reload"), questions: [question("Reload?", "Reload", ["Yes"])]});
		eq((await(reloadService.list())).length, 1, "question reload pending count");
		final project = ProjectRuntime.fromDirectory(reloaded.directory).project;
		InstanceRuntime.reload({
			directory: reloaded.directory,
			worktree: reloaded.worktree,
			project: project,
			services: [ctx->{id: InstanceServiceID.Command}],
		});
		eq(await(rejectionKind(reloadPromise)), "rejected", "question reload rejects");
		InstanceRuntime.dispose(reloaded.directory);
	}

	static function bootTempContext(label:String):InstanceContext {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), 'opencodehx-${label}-'));
		final project = ProjectRuntime.fromDirectory(root).project;
		final context = InstanceRuntime.boot({
			directory: root,
			worktree: root,
			project: project,
			services: [ctx->{id: InstanceServiceID.Command}],
		});
		if (context == null)
			throw '${label}: expected instance context';
		return context;
	}

	static function singleQuestion(text:String, header:String, first:String, second:String):Array<QuestionInfo> {
		return [question(text, header, [first, second])];
	}

	static function question(text:String, header:String, labels:Array<String>):QuestionInfo {
		return {
			question: text,
			header: header,
			options: [for (label in labels) {label: label, description: label}],
		};
	}

	static function answerText(answers:Array<QuestionAnswer>):String {
		final parts:Array<String> = [];
		for (answer in answers)
			parts.push(answer.join("/"));
		return parts.join("|");
	}

	static function requireTool(request:QuestionRequest):QuestionTool {
		final tool = request.tool;
		if (tool == null)
			throw "question expected tool metadata";
		return tool;
	}

	static function rejectionKind(promise:Promise<Array<QuestionAnswer>>):Promise<String> {
		return promise.then(_ -> "resolved").catchError(error -> {
			// JavaScript Promise rejection reasons are arbitrary host values.
			return Std.isOfType(error, QuestionRejectedError) ? "rejected" : "other";
		});
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
