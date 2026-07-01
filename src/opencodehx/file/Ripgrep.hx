package opencodehx.file;

import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.Json;
import opencodehx.externs.node.ChildProcess;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.util.Compare.compareString;

typedef FilesInput = {
	final cwd:String;
	@:optional final glob:Array<String>;
	@:optional final hidden:Bool;
	@:optional final follow:Bool;
	@:optional final maxDepth:Int;
}

typedef SearchInput = {
	final cwd:String;
	final pattern:String;
	@:optional final glob:Array<String>;
	@:optional final limit:Int;
	@:optional final follow:Bool;
	@:optional final file:Array<String>;
}

typedef SearchMatch = {
	final path:String;
	final line:String;
	final lineNumber:Int;
	final absoluteOffset:Int;
	final submatches:UnknownArray;
}

typedef SearchResult = {
	final items:Array<SearchMatch>;
	final partial:Bool;
}

class Ripgrep {
	public static function files(input:FilesInput):Array<String> {
		checkDir(input.cwd);
		final proc = run(input.cwd, filesArgs(input));
		if (proc.code != 0 && proc.code != 1)
			throw error(proc.stderr, proc.code);
		final output:Array<String> = [];
		for (line in proc.stdout.split("\n")) {
			if (line.length > 0)
				output.push(clean(line));
		}
		return output;
	}

	public static function search(input:SearchInput):SearchResult {
		checkDir(input.cwd);
		final result = run(input.cwd, searchArgs(input));
		if (result.code != 0 && result.code != 1 && result.code != 2)
			throw error(result.stderr, result.code);
		if (result.code == 1)
			return {items: [], partial: false};

		final items:Array<SearchMatch> = [];
		for (line in result.stdout.split("\n")) {
			if (line == "")
				continue;
			final event = UnknownNarrow.record(Unknown.fromBoundary(Json.parse(line)));
			if (event == null || UnknownNarrow.string(event.get("type")) != "match")
				continue;
			items.push(decodeMatch(event));
		}
		return {items: items, partial: result.code == 2};
	}

	public static function tree(cwd:String, ?limit:Int):String {
		final list = files({cwd: cwd});
		final dirs:Array<String> = [];
		for (file in list) {
			if (file.indexOf(".opencode") != -1)
				continue;
			final parts = file.split("/");
			if (parts.length < 2)
				continue;
			var current = "";
			for (index in 0...parts.length - 1) {
				current = current == "" ? parts[index] : current + "/" + parts[index];
				if (dirs.indexOf(current) == -1)
					dirs.push(current);
			}
		}
		dirs.sort(compareString);
		final max = limit == null ? dirs.length : limit;
		final shown = dirs.slice(0, max);
		if (dirs.length > shown.length)
			shown.push('[${dirs.length - shown.length} truncated]');
		return shown.join("\n");
	}

	static function filesArgs(input:FilesInput):Array<String> {
		final args = ["--no-config", "--files", "--glob=!.git/*"];
		if (input.follow == true)
			args.push("--follow");
		if (input.hidden != false)
			args.push("--hidden");
		if (input.hidden == false)
			args.push("--glob=!.*");
		if (input.maxDepth != null)
			args.push('--max-depth=${input.maxDepth}');
		if (input.glob != null) {
			for (glob in input.glob)
				args.push('--glob=${glob}');
		}
		args.push(".");
		return args;
	}

	static function searchArgs(input:SearchInput):Array<String> {
		final args = ["--no-config", "--json", "--hidden", "--glob=!.git/*", "--no-messages"];
		if (input.follow == true)
			args.push("--follow");
		if (input.glob != null) {
			for (glob in input.glob)
				args.push('--glob=${glob}');
		}
		if (input.limit != null)
			args.push('--max-count=${input.limit}');
		args.push("--");
		args.push(input.pattern);
		if (input.file != null) {
			for (file in input.file)
				args.push(file);
		} else {
			args.push(".");
		}
		return args;
	}

	static function run(cwd:String, args:Array<String>):{stdout:String, stderr:String, code:Int} {
		final result = ChildProcess.spawnSync("rg", args, {
			cwd: cwd,
			encoding: "utf8",
			windowsHide: true,
			maxBuffer: 20 * 1024 * 1024
		});
		if (result.error != null)
			throw result.error;
		return {
			stdout: result.stdout == null ? "" : result.stdout,
			stderr: result.stderr == null ? "" : result.stderr,
			code: result.status == null ? 1 : result.status,
		};
	}

	static function checkDir(cwd:String):Void {
		if (!Fs.existsSync(cwd) || !Fs.statSync(cwd).isDirectory()) {
			final error:Dynamic = 'No such file or directory: ${cwd}';
			throw error;
		}
	}

	static function clean(file:String):String {
		return new EReg("^\\./", "").replace(NodePath.normalize(file).split("\\").join("/"), "");
	}

	static function decodeMatch(event:UnknownRecord):SearchMatch {
		final data = requireRecord(event, "data");
		final lineNumber = requireNumber(data, "line_number");
		final absoluteOffset = requireNumber(data, "absolute_offset");
		final submatches = UnknownNarrow.array(data.get("submatches"));
		if (submatches == null)
			throw invalidJson("submatches");
		return {
			path: clean(requireTextRecord(data, "path")),
			line: requireTextRecord(data, "lines"),
			lineNumber: Std.int(lineNumber),
			absoluteOffset: Std.int(absoluteOffset),
			submatches: submatches,
		};
	}

	static function requireTextRecord(record:UnknownRecord, field:String):String {
		final nested = requireRecord(record, field);
		final text = UnknownNarrow.string(nested.get("text"));
		if (text == null)
			throw invalidJson(field + ".text");
		return text;
	}

	static function requireRecord(record:UnknownRecord, field:String):UnknownRecord {
		final value = UnknownNarrow.record(record.get(field));
		if (value == null)
			throw invalidJson(field);
		return value;
	}

	static function requireNumber(record:UnknownRecord, field:String):Float {
		final value = UnknownNarrow.number(record.get(field));
		if (value == null)
			throw invalidJson(field);
		return value;
	}

	static function error(stderr:String, code:Int):haxe.Exception {
		final message = StringTools.trim(stderr) == "" ? 'ripgrep failed with code ${code}' : StringTools.trim(stderr);
		return new haxe.Exception(message);
	}

	static function invalidJson(field:String):haxe.Exception {
		return new haxe.Exception('invalid ripgrep JSON match event: ${field}');
	}
}
