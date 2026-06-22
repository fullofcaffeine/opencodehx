package opencodehx.installation;

import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import haxe.DynamicAccess;
import haxe.Json;

using StringTools;

enum abstract InstallationMethod(String) from String to String {
	var Curl = "curl";
	var Npm = "npm";
	var Yarn = "yarn";
	var Pnpm = "pnpm";
	var Bun = "bun";
	var Brew = "brew";
	var Scoop = "scoop";
	var Choco = "choco";
	var UnknownMethod = "unknown";
}

enum abstract InstallationReleaseType(String) to String {
	var Patch = "patch";
	var Minor = "minor";
	var Major = "major";
}

typedef InstallationHttpRequest = {
	final url:String;
	final headers:DynamicAccess<String>;
}

typedef InstallationHttpResponse = {
	final status:Int;
	final body:String;
}

typedef InstallationCommand = {
	final command:String;
	final args:Array<String>;
	@:optional final cwd:String;
	@:optional final env:DynamicAccess<String>;
	@:optional final input:String;
}

typedef InstallationProcessResult = {
	final code:Int;
	final stdout:String;
	final stderr:String;
}

typedef InstallationDeps = {
	final execPath:String;
	final channel:String;
	final http:InstallationHttpRequest->InstallationHttpResponse;
	final run:InstallationCommand->InstallationProcessResult;
}

private typedef MethodCheck = {
	final name:InstallationMethod;
	final command:Array<String>;
}

class InstallationRuntime {
	public static function method(deps:InstallationDeps):InstallationMethod {
		if (isCurlPath(deps.execPath))
			return Curl;
		final exec = deps.execPath.toLowerCase();
		final checks = methodChecks();
		checks.sort((a, b) -> {
			final aMatches = exec.indexOf(a.name) != -1;
			final bMatches = exec.indexOf(b.name) != -1;
			if (aMatches && !bMatches)
				return -1;
			if (!aMatches && bMatches)
				return 1;
			return 0;
		});
		for (check in checks) {
			final output = text(deps, check.command);
			final installedName = switch check.name {
				case Brew | Choco | Scoop:
					"opencode";
				default:
					"opencode-ai";
			}
			if (output.indexOf(installedName) != -1)
				return methodFromString(check.name);
		}
		return UnknownMethod;
	}

	public static function latest(deps:InstallationDeps, ?installMethod:InstallationMethod):String {
		final detected = installMethod == null ? method(deps) : installMethod;
		return switch detected {
			case Brew:
				latestBrew(deps);
			case Npm | Bun | Pnpm:
				latestNpmRegistry(deps);
			case Choco:
				chocoVersion(fetchJson(deps,
					"https://community.chocolatey.org/api/v2/Packages?$filter=Id%20eq%20%27opencode%27%20and%20IsLatestVersion&$select=Version",
					header("Accept", "application/json;odata=verbose")));
			case Scoop:
				stringField(fetchJson(deps, "https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/opencode.json",
					header("Accept", "application/json")),
					"version", "scoop manifest");
			default:
				stripLeadingV(stringField(fetchJson(deps, "https://api.github.com/repos/anomalyco/opencode/releases/latest",
					header("Accept", "application/json")), "tag_name",
					"github release"));
		}
	}

	public static function getReleaseType(current:String, latest:String):InstallationReleaseType {
		final curr = parseSemver(current);
		final next = parseSemver(latest);
		if (next.major > curr.major)
			return Major;
		if (next.minor > curr.minor)
			return Minor;
		return Patch;
	}

	public static function upgrade(deps:InstallationDeps, installMethod:InstallationMethod, target:String):InstallationProcessResult {
		var result:InstallationProcessResult;
		switch installMethod {
			case Curl:
				final script = fetchText(deps, "https://opencode.ai/install", noHeaders());
				result = run(deps, {
					command: "bash",
					args: [],
					env: env("VERSION", target),
					input: script,
				});
			case Npm:
				result = run(deps, {command: "npm", args: ["install", "-g", 'opencode-ai@${target}']});
			case Pnpm:
				result = run(deps, {command: "pnpm", args: ["install", "-g", 'opencode-ai@${target}']});
			case Bun:
				result = run(deps, {command: "bun", args: ["install", "-g", 'opencode-ai@${target}']});
			case Brew:
				result = upgradeBrew(deps);
			case Choco:
				final outcome = run(deps, {command: "choco", args: ["upgrade", "opencode", '--version=${target}', "-y"]});
				result = outcome.code == 0 ? outcome : processResult(outcome.code, outcome.stdout, "not running from an elevated command shell");
			case Scoop:
				result = run(deps, {command: "scoop", args: ["install", 'opencode@${target}']});
			default:
				result = processResult(1, "", 'Unknown method: ${installMethod}');
		}
		if (result.code == 0)
			text(deps, [deps.execPath, "--version"]);
		return result;
	}

	public static function uninstallPackage(deps:InstallationDeps, installMethod:InstallationMethod):InstallationProcessResult {
		return switch installMethod {
			case Npm:
				run(deps, {command: "npm", args: ["uninstall", "-g", "opencode-ai"]});
			case Pnpm:
				run(deps, {command: "pnpm", args: ["uninstall", "-g", "opencode-ai"]});
			case Bun:
				run(deps, {command: "bun", args: ["remove", "-g", "opencode-ai"]});
			case Yarn:
				run(deps, {command: "yarn", args: ["global", "remove", "opencode-ai"]});
			case Brew:
				run(deps, {command: "brew", args: ["uninstall", "opencode"]});
			case Choco:
				run(deps, {command: "choco", args: ["uninstall", "opencode", "-y", "-r"]});
			case Scoop:
				run(deps, {command: "scoop", args: ["uninstall", "opencode"]});
			case Curl | UnknownMethod:
				processResult(0, "", "");
		}
	}

	static function latestBrew(deps:InstallationDeps):String {
		final formula = getBrewFormula(deps);
		if (formula.indexOf("/") != -1)
			return brewInfoVersion(parseJson(text(deps, ["brew", "info", "--json=v2", formula]), "brew info"));
		return stringField(field(fetchJson(deps, "https://formulae.brew.sh/api/formula/opencode.json", header("Accept", "application/json")), "versions",
			"brew formula"),
			"stable", "brew formula versions");
	}

	static function latestNpmRegistry(deps:InstallationDeps):String {
		final raw = text(deps, ["npm", "config", "get", "registry"]).trim();
		final base = raw == "" ? "https://registry.npmjs.org" : raw;
		final registry = base.endsWith("/") ? base.substr(0, base.length - 1) : base;
		return stringField(fetchJson(deps, '${registry}/opencode-ai/${deps.channel}', header("Accept", "application/json")), "version", "npm package");
	}

	static function upgradeBrew(deps:InstallationDeps):InstallationProcessResult {
		final formula = getBrewFormula(deps);
		final brewEnv = env("HOMEBREW_NO_AUTO_UPDATE", "1");
		if (formula.indexOf("/") != -1) {
			final tap = run(deps, {command: "brew", args: ["tap", "anomalyco/tap"], env: brewEnv});
			if (tap.code != 0)
				return tap;
			final repo = text(deps, ["brew", "--repo", "anomalyco/tap"]).trim();
			if (repo != "") {
				final pull = run(deps, {
					command: "git",
					args: ["pull", "--ff-only"],
					cwd: repo,
					env: brewEnv
				});
				if (pull.code != 0)
					return pull;
			}
		}
		return run(deps, {command: "brew", args: ["upgrade", formula], env: brewEnv});
	}

	static function getBrewFormula(deps:InstallationDeps):String {
		final tapFormula = text(deps, ["brew", "list", "--formula", "anomalyco/tap/opencode"]);
		if (tapFormula.indexOf("opencode") != -1)
			return "anomalyco/tap/opencode";
		final coreFormula = text(deps, ["brew", "list", "--formula", "opencode"]);
		if (coreFormula.indexOf("opencode") != -1)
			return "opencode";
		return "opencode";
	}

	static function methodChecks():Array<MethodCheck> {
		return [
			{name: Npm, command: ["npm", "list", "-g", "--depth=0"]},
			{name: Yarn, command: ["yarn", "global", "list"]},
			{name: Pnpm, command: ["pnpm", "list", "-g", "--depth=0"]},
			{name: Bun, command: ["bun", "pm", "ls", "-g"]},
			{name: Brew, command: ["brew", "list", "--formula", "opencode"]},
			{name: Scoop, command: ["scoop", "list", "opencode"]},
			{name: Choco, command: ["choco", "list", "--limit-output", "opencode"]},
		];
	}

	static function methodFromString(name:String):InstallationMethod {
		return switch name {
			case "curl":
				Curl;
			case "npm":
				Npm;
			case "yarn":
				Yarn;
			case "pnpm":
				Pnpm;
			case "bun":
				Bun;
			case "brew":
				Brew;
			case "scoop":
				Scoop;
			case "choco":
				Choco;
			default:
				UnknownMethod;
		}
	}

	static function fetchJson(deps:InstallationDeps, url:String, headers:DynamicAccess<String>):Unknown {
		return parseJson(fetchText(deps, url, headers), url);
	}

	static function fetchText(deps:InstallationDeps, url:String, headers:DynamicAccess<String>):String {
		final response = deps.http({url: url, headers: headers});
		if (response.status < 200 || response.status >= 300)
			throw 'installation HTTP request failed (${response.status}): ${url}';
		return response.body;
	}

	static function text(deps:InstallationDeps, command:Array<String>):String {
		return run(deps, {command: command[0], args: command.slice(1)}).stdout;
	}

	static function run(deps:InstallationDeps, command:InstallationCommand):InstallationProcessResult {
		return deps.run(command);
	}

	static function noHeaders():DynamicAccess<String> {
		return new DynamicAccess<String>();
	}

	static function header(name:String, value:String):DynamicAccess<String> {
		final out = new DynamicAccess<String>();
		out.set(name, value);
		return out;
	}

	static function env(name:String, value:String):DynamicAccess<String> {
		final out = new DynamicAccess<String>();
		out.set(name, value);
		return out;
	}

	static function processResult(code:Int, stdout:String, stderr:String):InstallationProcessResult {
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function isCurlPath(execPath:String):Bool {
		return execPath.indexOf("/.opencode/bin") != -1
			|| execPath.indexOf("\\.opencode\\bin") != -1
			|| execPath.indexOf("/.local/bin") != -1
			|| execPath.indexOf("\\.local\\bin") != -1;
	}

	static function stripLeadingV(value:String):String {
		return value.startsWith("v") ? value.substr(1) : value;
	}

	static function parseSemver(version:String):{major:Int, minor:Int} {
		final clean = stripLeadingV(version);
		final parts = clean.split(".");
		return {
			major: parseInt(parts.length > 0 ? parts[0] : "0"),
			minor: parseInt(parts.length > 1 ? parts[1] : "0"),
		};
	}

	static function parseInt(value:String):Int {
		final parsed = Std.parseInt(value);
		return parsed == null ? 0 : parsed;
	}

	static function brewInfoVersion(data:Unknown):String {
		final formulae = arrayField(data, "formulae", "brew info");
		if (formulae.length == 0)
			throw "brew info response did not include formulae";
		return stringField(field(formulae.get(0), "versions", "brew info formula"), "stable", "brew info versions");
	}

	static function chocoVersion(data:Unknown):String {
		final results = arrayField(field(data, "d", "chocolatey response"), "results", "chocolatey response");
		if (results.length == 0)
			throw "chocolatey response did not include results";
		return stringField(results.get(0), "Version", "chocolatey package");
	}

	/**
	 * External version APIs return untrusted JSON. Keep the weak boundary as
	 * `Unknown`: every field read below is guarded with TS runtime checks and
	 * callers receive typed strings/arrays or a deterministic error.
	 */
	static function parseJson(text:String, source:String):Unknown {
		try {
			return Unknown.fromBoundary(Json.parse(text));
		} catch (error:haxe.Exception) {
			throw 'invalid installation JSON from ${source}: ${error.message}';
		}
	}

	static function field(data:Unknown, name:String, source:String):Unknown {
		final record = UnknownNarrow.record(data);
		if (record == null || !record.hasOwn(name))
			throw 'missing ${name} in ${source}';
		final value = record.get(name);
		if (UnknownNarrow.isNull(value) || UnknownNarrow.isUndefined(value))
			throw 'missing ${name} in ${source}';
		return value;
	}

	static function stringField(data:Unknown, name:String, source:String):String {
		final value = field(data, name, source);
		final string = UnknownNarrow.string(value);
		if (string == null)
			throw 'expected ${name} in ${source} to be a string';
		return string;
	}

	static function arrayField(data:Unknown, name:String, source:String):UnknownArray {
		final value = field(data, name, source);
		final array = UnknownNarrow.array(value);
		if (array == null)
			throw 'expected ${name} in ${source} to be an array';
		return array;
	}
}
