package opencodehx.tui;

using StringTools;

abstract TuiProviderID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):TuiProviderID {
		return new TuiProviderID(value);
	}

	public inline function toString():String {
		return this;
	}
}

abstract TuiModelID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):TuiModelID {
		return new TuiModelID(value);
	}

	public inline function toString():String {
		return this;
	}
}

abstract TuiSessionID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):TuiSessionID {
		return new TuiSessionID(value);
	}

	public inline function toString():String {
		return this;
	}
}

abstract TuiPermissionID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):TuiPermissionID {
		return new TuiPermissionID(value);
	}

	public inline function toString():String {
		return this;
	}
}

typedef TuiDialogRow = {
	final label:String;
	final text:String;
}

typedef TuiModelRef = {
	final providerID:TuiProviderID;
	final modelID:TuiModelID;
}

typedef TuiModelOption = {
	final value:TuiModelRef;
	final title:String;
	final providerName:String;
	final category:String;
	final current:Bool;
	final favorite:Bool;
	final free:Bool;
	final disabled:Bool;
}

typedef TuiProviderAuthMethod = {
	final kind:TuiProviderAuthKind;
	final label:String;
}

typedef TuiProviderOption = {
	final providerID:TuiProviderID;
	final title:String;
	final category:String;
	final connected:Bool;
	final description:String;
	final authMethods:Array<TuiProviderAuthMethod>;
}

typedef TuiSessionOption = {
	final sessionID:TuiSessionID;
	final title:String;
	final category:String;
	final footer:String;
	final current:Bool;
	final busy:Bool;
}

typedef TuiPermissionRequest = {
	final id:TuiPermissionID;
	final subject:TuiPermissionSubject;
	final always:Array<String>;
	final parentSession:Bool;
}

enum abstract TuiProviderAuthKind(String) to String {
	var ApiKey = "api";
	var OAuth = "oauth";
}

enum abstract TuiPermissionReplyKind(String) to String {
	var Once = "once";
	var Always = "always";
	var Reject = "reject";
}

enum TuiPermissionSubject {
	EditFile(path:String, diffPreview:String);
	ReadFile(path:String);
	BashCommand(description:String, command:String);
}

enum TuiPermissionDecision {
	PermissionAllowed(reply:TuiPermissionReplyKind);
	PermissionRejected(message:String);
}

enum TuiDialogAction {
	ModelSelected(value:TuiModelRef);
	ProviderAuthRequested(providerID:TuiProviderID, method:TuiProviderAuthKind);
	SessionSelected(sessionID:TuiSessionID);
	PermissionReplied(requestID:TuiPermissionID, decision:TuiPermissionDecision);
}

class TuiDialogReplay {
	public static function fixtureRows():Array<TuiDialogRow> {
		final out:Array<TuiDialogRow> = [];
		pushRows(out, modelRows(modelFixture()));
		pushRows(out, providerRows(providerFixture()));
		pushRows(out, sessionRows(sessionFixture()));
		pushRows(out, permissionRows(permissionFixture()));
		out.push({label: "Action", text: actionText(selectModel(modelFixture(), 0))});
		out.push({label: "Action", text: actionText(selectProvider(providerFixture(), 1))});
		out.push({label: "Action", text: actionText(selectSession(sessionFixture(), 0))});
		out.push({label: "Action", text: actionText(replyPermission(permissionFixture(), Once))});
		out.push({label: "Action", text: actionText(replyPermission(permissionFixture(), Reject, "Use a smaller edit"))});
		return out;
	}

	public static function modelFixture():Array<TuiModelOption> {
		return [
			{
				value: {providerID: TuiProviderID.make("openai"), modelID: TuiModelID.make("gpt-5.2")},
				title: "GPT-5.2",
				providerName: "OpenAI",
				category: "Recent",
				current: true,
				favorite: true,
				free: false,
				disabled: false,
			},
			{
				value: {providerID: TuiProviderID.make("opencode"), modelID: TuiModelID.make("opencode-free")},
				title: "OpenCode Free",
				providerName: "OpenCode",
				category: "OpenCode",
				current: false,
				favorite: false,
				free: true,
				disabled: false,
			},
		];
	}

	public static function providerFixture():Array<TuiProviderOption> {
		return [
			{
				providerID: TuiProviderID.make("opencode"),
				title: "OpenCode",
				category: "Popular",
				connected: true,
				description: "(Recommended)",
				authMethods: [],
			},
			{
				providerID: TuiProviderID.make("openai"),
				title: "OpenAI",
				category: "Popular",
				connected: false,
				description: "(ChatGPT Plus/Pro or API key)",
				authMethods: [
					{
						kind: ApiKey,
						label: "API key"
					}
				],
			},
			{
				providerID: TuiProviderID.make("anthropic"),
				title: "Anthropic",
				category: "Popular",
				connected: false,
				description: "(API key)",
				authMethods: [{kind: ApiKey, label: "API key"}],
			},
		];
	}

	public static function sessionFixture():Array<TuiSessionOption> {
		return [
			{
				sessionID: TuiSessionID.make("ses_today"),
				title: "Refactor compiler seam",
				category: "Today",
				footer: "10:24",
				current: true,
				busy: true,
			},
			{
				sessionID: TuiSessionID.make("ses_yesterday"),
				title: "Port config loader",
				category: "Yesterday",
				footer: "18:40",
				current: false,
				busy: false,
			},
		];
	}

	public static function permissionFixture():TuiPermissionRequest {
		return {
			id: TuiPermissionID.make("permission_000001"),
			subject: EditFile("src/opencodehx/Main.hx", "- old\n+ new"),
			always: ["edit:src/opencodehx/*"],
			parentSession: true,
		};
	}

	public static function modelRows(options:Array<TuiModelOption>):Array<TuiDialogRow> {
		final out:Array<TuiDialogRow> = [{label: "Dialog", text: "Select model"}];
		for (option in options) {
			final markers:Array<String> = [];
			if (option.current)
				markers.push("current");
			if (option.favorite)
				markers.push("favorite");
			if (option.free)
				markers.push("free");
			if (option.disabled)
				markers.push("disabled");
			out.push({
				label: "Option",
				text: '${option.category}: ${option.title} - ${option.providerName}${markerSuffix(markers)}',
			});
		}
		return out;
	}

	public static function providerRows(options:Array<TuiProviderOption>):Array<TuiDialogRow> {
		final out:Array<TuiDialogRow> = [{label: "Dialog", text: "Connect a provider"}];
		for (option in options) {
			final markers = option.connected ? " [connected]" : "";
			out.push({
				label: "Option",
				text: '${option.category}: ${option.title} ${option.description}${markers}',
			});
		}
		return out;
	}

	public static function sessionRows(options:Array<TuiSessionOption>):Array<TuiDialogRow> {
		final out:Array<TuiDialogRow> = [{label: "Dialog", text: "Sessions"}];
		for (option in options) {
			final markers:Array<String> = [];
			if (option.current)
				markers.push("current");
			if (option.busy)
				markers.push("busy");
			out.push({
				label: "Option",
				text: '${option.category}: ${option.title} ${option.footer}${markerSuffix(markers)}',
			});
		}
		return out;
	}

	public static function permissionRows(request:TuiPermissionRequest):Array<TuiDialogRow> {
		return [
			{label: "Dialog", text: "Permission required"},
			{label: "Request", text: permissionTitle(request.subject)},
			{label: "Body", text: permissionBody(request.subject)},
			{label: "Choices", text: "Allow once | Allow always | Reject"},
			{label: "Always", text: request.always.join(", ")},
			{label: "Reject", text: "Tell OpenCode what to do differently"},
		];
	}

	public static function selectModel(options:Array<TuiModelOption>, index:Int):TuiDialogAction {
		return ModelSelected(optionAt(options, index, "model").value);
	}

	public static function selectProvider(options:Array<TuiProviderOption>, index:Int):TuiDialogAction {
		final option = optionAt(options, index, "provider");
		final method = option.authMethods.length == 0 ? ApiKey : option.authMethods[0].kind;
		return ProviderAuthRequested(option.providerID, method);
	}

	public static function selectSession(options:Array<TuiSessionOption>, index:Int):TuiDialogAction {
		return SessionSelected(optionAt(options, index, "session").sessionID);
	}

	public static function replyPermission(request:TuiPermissionRequest, reply:TuiPermissionReplyKind, message:Null<String> = null):TuiDialogAction {
		if (reply == Reject)
			return PermissionReplied(request.id, PermissionRejected(message == null ? "" : message));
		return PermissionReplied(request.id, PermissionAllowed(reply));
	}

	public static function actionText(action:TuiDialogAction):String {
		return switch action {
			case ModelSelected(value):
				'model ${value.providerID.toString()}/${value.modelID.toString()}';
			case ProviderAuthRequested(providerID, method):
				'provider ${providerID.toString()} -> ${method}';
			case SessionSelected(sessionID):
				'session ${sessionID.toString()}';
			case PermissionReplied(_, decision):
				switch decision {
					case PermissionAllowed(reply):
						'permission ${reply}';
					case PermissionRejected(message):
						'permission reject: ${message}';
				}
		}
	}

	static function permissionTitle(subject:TuiPermissionSubject):String {
		return switch subject {
			case EditFile(path, _):
				'Edit ${path}';
			case ReadFile(path):
				'Read ${path}';
			case BashCommand(description, _):
				description.trim().length == 0 ? "Shell command" : description;
		}
	}

	static function permissionBody(subject:TuiPermissionSubject):String {
		return switch subject {
			case EditFile(_, diffPreview):
				diffPreview.split("\n").join(" ");
			case ReadFile(path):
				'Path: ${path}';
			case BashCommand(_, command):
				'$ ${command}';
		}
	}

	static function markerSuffix(markers:Array<String>):String {
		return markers.length == 0 ? "" : ' [${markers.join(", ")}]';
	}

	static function pushRows(out:Array<TuiDialogRow>, rows:Array<TuiDialogRow>):Void {
		for (row in rows)
			out.push(row);
	}

	static function optionAt<T>(options:Array<T>, index:Int, label:String):T {
		if (index < 0 || index >= options.length)
			throw 'Unknown ${label} option index ${index}';
		return options[index];
	}
}
