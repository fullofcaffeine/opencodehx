package opencodehx.format;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.DynamicAccess;
import js.lib.Promise;
import opencodehx.externs.node.ChildProcess;
import opencodehx.externs.node.ChildProcess.SpawnSyncOptions;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;

typedef FormatterContext = {
	final directory:String;
	final worktree:String;
}

typedef FormatterInfo = {
	final name:String;
	final extensions:Array<String>;
	final enabled:FormatterContext->Promise<Null<Array<String>>>;
	@:optional final environment:DynamicAccess<String>;
}

typedef FormatterStatus = {
	final name:String;
	final extensions:Array<String>;
	final enabled:Bool;
}

typedef FormatterConfigEntry = {
	final disabled:Bool;
	final command:Null<Array<String>>;
	final environment:Null<DynamicAccess<String>>;
	final extensions:Null<Array<String>>;
}

typedef FormatterCommand = {
	final command:String;
	final args:Array<String>;
	final cwd:String;
	final env:DynamicAccess<String>;
}

typedef FormatterRunResult = {
	final code:Int;
}

typedef FormatterRunner = FormatterCommand->Promise<FormatterRunResult>;

typedef FormatterCheckResult = {
	final item:FormatterInfo;
	final command:Null<Array<String>>;
}

typedef FormatterRunnable = {
	final item:FormatterInfo;
	final command:Array<String>;
}

class FormatRuntime {
	final context:FormatterContext;
	final formatters:DynamicAccess<FormatterInfo>;
	final runner:FormatterRunner;
	final commands:DynamicAccess<Null<Array<String>>> = new DynamicAccess();

	public function new(context:FormatterContext, config:Dynamic, ?builtins:Array<FormatterInfo>, ?runner:FormatterRunner) {
		this.context = context;
		this.runner = runner == null ? defaultRunner : runner;
		this.formatters = buildFormatters(config, builtins == null ? defaultBuiltins() : builtins);
	}

	public function init():Void {}

	@:async
	public function status():Promise<Array<FormatterStatus>> {
		final result:Array<FormatterStatus> = [];
		for (name in formatters.keys()) {
			final item = formatters.get(name);
			result.push({
				name: item.name,
				extensions: item.extensions,
				enabled: @:await isEnabled(item),
			});
		}
		return result;
	}

	@:async
	public function file(filepath:String):Promise<Bool> {
		final matches = @:await matchingFormatters(NodePath.extname(filepath));
		if (matches.length == 0)
			return false;
		for (match in matches) {
			final command = [for (part in match.command) StringTools.replace(part, "$FILE", filepath)];
			final env = mergeEnv(match.item.environment);
			@:await runner({
				command: command[0],
				args: command.slice(1),
				cwd: context.directory,
				env: env,
			});
		}
		return true;
	}

	@:async
	function matchingFormatters(ext:String):Promise<Array<FormatterRunnable>> {
		final pending:Array<Promise<FormatterCheckResult>> = [];
		for (name in formatters.keys()) {
			final item = formatters.get(name);
			if (item.extensions.indexOf(ext) == -1)
				continue;
			pending.push(checkFormatter(item));
		}
		final checked = @:await Promise.all(pending);
		final result:Array<FormatterRunnable> = [];
		for (item in checked) {
			final command = item.command;
			if (command != null)
				result.push({item: item.item, command: command});
		}
		return result;
	}

	@:async
	function checkFormatter(item:FormatterInfo):Promise<FormatterCheckResult> {
		return {
			item: item,
			command: @:await commandFor(item),
		};
	}

	@:async
	function commandFor(item:FormatterInfo):Promise<Null<Array<String>>> {
		if (commands.exists(item.name))
			return commands.get(item.name);
		final command = @:await item.enabled(context);
		commands.set(item.name, command);
		return command;
	}

	@:async
	function isEnabled(item:FormatterInfo):Promise<Bool> {
		return (@:await commandFor(item)) != null;
	}

	static function buildFormatters(config:Dynamic, builtins:Array<FormatterInfo>):DynamicAccess<FormatterInfo> {
		final out = new DynamicAccess<FormatterInfo>();
		if (config == null)
			return out;
		final raw = Unknown.fromBoundary(config);
		final enabled = UnknownNarrow.bool(raw);
		if (enabled == false)
			return out;
		for (item in builtins) {
			out.set(item.name, item);
		}
		if (enabled == true)
			return out;
		final record = UnknownNarrow.record(raw);
		if (record == null)
			return out;
		for (name in record.keys()) {
			final entry = decodeEntry(record.get(name));
			final ruffDisabled = (name == "ruff" || name == "uv") && (disabled(record, "ruff") || disabled(record, "uv"));
			if (ruffDisabled) {
				out.remove("ruff");
				out.remove("uv");
				continue;
			}
			if (entry.disabled) {
				out.remove(name);
				continue;
			}
			final builtIn = out.get(name);
			out.set(name, mergeFormatter(name, builtIn, entry));
		}
		return out;
	}

	static function mergeFormatter(name:String, builtIn:Null<FormatterInfo>, entry:FormatterConfigEntry):FormatterInfo {
		final command = entry.command;
		final extensions = entry.extensions != null ? entry.extensions : builtIn == null ? [] : builtIn.extensions;
		final environment = entry.environment != null ? entry.environment : builtIn == null ? null : builtIn.environment;
		return {
			name: name,
			extensions: extensions,
			environment: environment,
			enabled: command == null && builtIn != null ? builtIn.enabled : _ -> Promise.resolve(command),
		};
	}

	static function decodeEntry(raw:Unknown):FormatterConfigEntry {
		final record = UnknownNarrow.record(raw);
		if (record == null) {
			return {
				disabled: false,
				command: null,
				environment: null,
				extensions: null
			};
		}
		return {
			disabled: UnknownNarrow.bool(record.get("disabled")) == true,
			command: stringArray(record.get("command")),
			environment: stringMap(record.get("environment")),
			extensions: stringArray(record.get("extensions")),
		};
	}

	static function stringArray(raw:Unknown):Null<Array<String>> {
		final items = UnknownNarrow.array(raw);
		if (items == null)
			return null;
		final out:Array<String> = [];
		for (index in 0...items.length) {
			final item = UnknownNarrow.string(items.get(index));
			if (item != null)
				out.push(item);
		}
		return out;
	}

	static function stringMap(raw:Unknown):Null<DynamicAccess<String>> {
		final record = UnknownNarrow.record(raw);
		if (record == null)
			return null;
		final out = new DynamicAccess<String>();
		for (field in record.keys()) {
			final value = UnknownNarrow.string(record.get(field));
			if (value != null)
				out.set(field, value);
		}
		return out;
	}

	static function disabled(config:UnknownRecord, name:String):Bool {
		final entry = UnknownNarrow.record(config.get(name));
		return entry != null && UnknownNarrow.bool(entry.get("disabled")) == true;
	}

	static function mergeEnv(extra:Null<DynamicAccess<String>>):DynamicAccess<String> {
		final env = NodeProcess.env();
		if (extra != null) {
			for (key in extra.keys()) {
				env.set(key, extra.get(key));
			}
		}
		return env;
	}

	static function defaultRunner(command:FormatterCommand):Promise<FormatterRunResult> {
		final options:SpawnSyncOptions = {
			cwd: command.cwd,
			encoding: "utf8",
			env: command.env,
			windowsHide: true,
		};
		final result = ChildProcess.spawnSync(command.command, command.args, options);
		return Promise.resolve({code: result.status == null ? 1 : result.status});
	}

	public static function defaultBuiltins():Array<FormatterInfo> {
		return [
			staticCommand("gofmt", [".go"], ["gofmt", "-w", "$FILE"]),
			staticCommand("mix", [".ex", ".exs", ".eex", ".heex", ".leex", ".neex", ".sface"], ["mix", "format", "$FILE"]),
			staticCommand("ruff", [".py", ".pyi"], ["ruff", "format", "$FILE"]),
			staticCommand("uv", [".py", ".pyi"], ["uv", "format", "--", "$FILE"]),
		];
	}

	public static function staticCommand(name:String, extensions:Array<String>, command:Array<String>, ?environment:DynamicAccess<String>):FormatterInfo {
		return {
			name: name,
			extensions: extensions,
			environment: environment,
			enabled: _ -> Promise.resolve(command),
		};
	}
}
