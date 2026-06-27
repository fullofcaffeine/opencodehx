package opencodehx.question;

import js.lib.Error;
import js.lib.Promise;
import opencodehx.project.InstanceRuntime;
import opencodehx.project.InstanceRuntime.InstanceContext;
import opencodehx.session.MessageID;
import opencodehx.session.SessionID;

abstract QuestionID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):QuestionID {
		return new QuestionID(value);
	}

	public inline function toString():String {
		return this;
	}
}

typedef QuestionOption = {
	final label:String;
	final description:String;
}

typedef QuestionInfo = {
	final question:String;
	final header:String;
	final options:Array<QuestionOption>;
	@:optional final multiple:Bool;
	@:optional final custom:Bool;
}

typedef QuestionTool = {
	final messageID:MessageID;
	final callID:String;
}

typedef QuestionAnswer = Array<String>;

typedef QuestionAskInput = {
	final sessionID:SessionID;
	final questions:Array<QuestionInfo>;
	@:optional final tool:QuestionTool;
}

typedef QuestionRequest = {
	final id:QuestionID;
	final sessionID:SessionID;
	final questions:Array<QuestionInfo>;
	@:optional final tool:QuestionTool;
}

typedef QuestionReplyInput = {
	final requestID:QuestionID;
	final answers:Array<QuestionAnswer>;
}

enum QuestionEvent {
	QuestionAsked(request:QuestionRequest);
	QuestionReplied(sessionID:SessionID, requestID:QuestionID, answers:Array<QuestionAnswer>);
	QuestionRejected(sessionID:SessionID, requestID:QuestionID);
}

private typedef PendingQuestion = {
	final info:QuestionRequest;
	final resolve:Array<QuestionAnswer>->Void;
	final reject:QuestionRejectedError->Void;
}

class QuestionRejectedError extends Error {
	public function new() {
		super("The user dismissed this question");
	}
}

class QuestionService {
	final pending:Map<String, PendingQuestion> = new Map();
	final order:Array<QuestionID> = [];
	final events:Array<QuestionEvent> = [];
	var nextID = 1;
	var disposed = false;

	public function new() {}

	public function ask(input:QuestionAskInput):Promise<Array<QuestionAnswer>> {
		if (disposed)
			return Promise.reject(new QuestionRejectedError());
		final id = nextQuestionID();
		final request:QuestionRequest = {
			id: id,
			sessionID: input.sessionID,
			questions: input.questions.copy(),
			tool: input.tool,
		};
		return new Promise<Array<QuestionAnswer>>((resolve, reject) -> {
			final rejectQuestion = (error:QuestionRejectedError) -> reject(error);
			pending.set(id.toString(), {
				info: request,
				resolve: resolve,
				reject: rejectQuestion,
			});
			order.push(id);
			events.push(QuestionAsked(request));
		});
	}

	public function reply(input:QuestionReplyInput):Promise<Void> {
		final existing = remove(input.requestID);
		if (existing == null)
			return resolvedVoid();
		events.push(QuestionReplied(existing.info.sessionID, existing.info.id, cloneAnswers(input.answers)));
		existing.resolve(cloneAnswers(input.answers));
		return resolvedVoid();
	}

	public function reject(requestID:QuestionID):Promise<Void> {
		final existing = remove(requestID);
		if (existing == null)
			return resolvedVoid();
		events.push(QuestionRejected(existing.info.sessionID, existing.info.id));
		existing.reject(new QuestionRejectedError());
		return resolvedVoid();
	}

	public function list():Promise<Array<QuestionRequest>> {
		final out:Array<QuestionRequest> = [];
		for (id in order) {
			final existing = pending.get(id.toString());
			if (existing != null)
				out.push(existing.info);
		}
		return Promise.resolve(out);
	}

	public function eventHistory():Array<QuestionEvent> {
		return events.copy();
	}

	public function dispose():Void {
		if (disposed)
			return;
		disposed = true;
		final ids = order.copy();
		for (id in ids) {
			final existing = remove(id);
			if (existing != null) {
				events.push(QuestionRejected(existing.info.sessionID, existing.info.id));
				existing.reject(new QuestionRejectedError());
			}
		}
	}

	function nextQuestionID():QuestionID {
		final id = QuestionID.make('que_${nextID}');
		nextID += 1;
		return id;
	}

	function remove(id:QuestionID):Null<PendingQuestion> {
		final key = id.toString();
		final existing = pending.get(key);
		if (existing == null)
			return null;
		pending.remove(key);
		order.remove(id);
		return existing;
	}

	static function cloneAnswers(answers:Array<QuestionAnswer>):Array<QuestionAnswer> {
		return [for (answer in answers) answer.copy()];
	}

	static function resolvedVoid():Promise<Void> {
		return new Promise<Void>((resolve, _) -> {
			// Promise<Void> needs a zero-arg resolver shape in Haxe, while the
			// JavaScript Promise constructor provides a value-taking callback.
			final done:Void->Void = cast resolve;
			done();
		});
	}
}

class QuestionRuntime {
	static final services:Map<String, QuestionService> = new Map();
	static var unsubscribe:Null<Void->Void> = null;

	public static function forContext(context:InstanceContext):QuestionService {
		ensureSubscribed();
		final key = context.directory;
		final existing = services.get(key);
		if (existing != null)
			return existing;
		final service = new QuestionService();
		services.set(key, service);
		return service;
	}

	public static function reset():Void {
		for (service in services) {
			service.dispose();
		}
		services.clear();
		if (unsubscribe != null) {
			unsubscribe();
			unsubscribe = null;
		}
	}

	static function ensureSubscribed():Void {
		if (unsubscribe != null)
			return;
		unsubscribe = InstanceRuntime.subscribe(event -> {
			final service = services.get(event.directory);
			if (service == null)
				return;
			services.remove(event.directory);
			service.dispose();
		});
	}
}
