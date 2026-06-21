package opencodehx.npm;

import genes.ts.Unknown;
import haxe.Json;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.interop.UnknownAccess;

using StringTools;

typedef NpmHttpResponse = {
	final ok:Bool;
	final body:String;
}

typedef NpmReifyRequest = {
	final dir:String;
	final add:Array<String>;
}

typedef NpmReifyEdge = {
	final name:String;
	final path:String;
}

typedef NpmReifyResult = {
	final edges:Array<NpmReifyEdge>;
}

typedef NpmEntryPoint = {
	final directory:String;
	final entrypoint:Null<String>;
}

typedef NpmInstallPackage = {
	final name:String;
	@:optional final version:String;
}

typedef NpmInstallInput = {
	final add:Array<NpmInstallPackage>;
}

typedef NpmDeps = {
	final cache:String;
	final http:String->NpmHttpResponse;
	final reify:NpmReifyRequest->NpmReifyResult;
	@:optional final canWrite:String->Bool;
	@:optional final resolveEntryPoint:(String, String) -> Null<String>;
}

typedef SemverParts = {
	final major:Int;
	final minor:Int;
	final patch:Int;
}

class Npm {
	static final WINDOWS_ILLEGAL = ["<", ">", ":", "\"", "|", "?", "*"];
	static final DEPENDENCY_FIELDS = ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"];

	public static function sanitize(spec:String):String {
		if (NodeProcess.platform() != "win32")
			return spec;
		final out = new StringBuf();
		for (index in 0...spec.length) {
			final char = spec.charAt(index);
			out.add(WINDOWS_ILLEGAL.indexOf(char) == -1 && spec.charCodeAt(index) >= 32 ? char : "_");
		}
		return out.toString();
	}

	public static function cacheDirectory(deps:NpmDeps, pkg:String):String {
		return NodePath.join(NodePath.join(deps.cache, "packages"), sanitize(pkg));
	}

	public static function packageName(spec:String):String {
		final normalized = spec.startsWith("npm:") ? spec.substr(4) : spec;
		if (normalized.startsWith("@")) {
			final slash = normalized.indexOf("/");
			if (slash == -1)
				return normalized;
			final version = normalized.indexOf("@", slash + 1);
			return version == -1 ? normalized : normalized.substr(0, version);
		}
		final version = normalized.indexOf("@");
		return version == -1 ? normalized : normalized.substr(0, version);
	}

	public static function add(deps:NpmDeps, pkg:String):NpmEntryPoint {
		final dir = cacheDirectory(deps, pkg);
		final name = packageName(pkg);
		if (Fs.existsSync(dir))
			return entryPoint(deps, name, NodePath.join(NodePath.join(dir, "node_modules"), name));

		final tree = deps.reify({dir: dir, add: [pkg]});
		if (tree.edges.length == 0)
			throw 'Npm.add failed for ${pkg} in ${dir}';
		final first = tree.edges[0];
		return entryPoint(deps, first.name, first.path);
	}

	public static function install(deps:NpmDeps, dir:String, ?input:NpmInstallInput):Void {
		if (!canWrite(deps, dir))
			return;

		final add = installSpecs(input);
		if (!Fs.existsSync(NodePath.join(dir, "node_modules"))) {
			deps.reify({dir: dir, add: add});
			return;
		}

		final pkg = readJson(NodePath.join(dir, "package.json"));
		final lock = readJson(NodePath.join(dir, "package-lock.json"));
		final declared = dependencyNames(pkg);
		if (input != null) {
			for (item in input.add)
				pushUnique(declared, item.name);
		}

		final packages = field(lock, "packages");
		final root = packages == null ? emptyObject() : field(packages, "");
		final locked = root == null ? [] : dependencyNames(root);

		for (name in declared) {
			if (locked.indexOf(name) == -1) {
				deps.reify({dir: dir, add: add});
				return;
			}
		}
	}

	public static function outdated(deps:NpmDeps, pkg:String, cachedVersion:String):Bool {
		final response = deps.http('https://registry.npmjs.org/${pkg}');
		if (!response.ok)
			return false;

		final data = parseJson(response.body);
		final tags = field(data, "dist-tags");
		if (tags == null)
			return false;
		final latest = stringField(tags, "latest");
		if (latest == null || latest == "")
			return false;

		return isRange(cachedVersion) ? !satisfies(latest, cachedVersion) : semverLt(cachedVersion, latest);
	}

	public static function which(deps:NpmDeps, pkg:String):Null<String> {
		final dir = cacheDirectory(deps, pkg);
		final binDir = NodePath.join(NodePath.join(dir, "node_modules"), ".bin");
		try {
			final existing = pickBinary(pkg, dir, binDir);
			if (existing != null)
				return NodePath.join(binDir, existing);

			final lock = NodePath.join(dir, "package-lock.json");
			if (Fs.existsSync(lock))
				Fs.rmSync(lock, {force: true});

			add(deps, pkg);
			final resolved = pickBinary(pkg, dir, binDir);
			return resolved == null ? null : NodePath.join(binDir, resolved);
			// Dynamic is required here because Node filesystem calls and the injected
			// reify boundary can throw native JS errors that Haxe cannot type more
			// precisely. The public result contains the failure as a null lookup.
		} catch (error:Dynamic) {
			return null;
		}
	}

	static function entryPoint(deps:NpmDeps, name:String, dir:String):NpmEntryPoint {
		final resolve = deps.resolveEntryPoint;
		return {
			directory: dir,
			entrypoint: resolve == null ? null : resolve(name, dir),
		};
	}

	static function installSpecs(input:Null<NpmInstallInput>):Array<String> {
		if (input == null)
			return [];
		final out:Array<String> = [];
		for (item in input.add) {
			out.push(item.version == null || item.version == "" ? item.name : '${item.name}@${item.version}');
		}
		return out;
	}

	static function canWrite(deps:NpmDeps, dir:String):Bool {
		final check = deps.canWrite;
		if (check != null)
			return check(dir);
		try {
			return Fs.existsSync(dir) && Fs.statSync(dir).isDirectory();
			// Dynamic is required here because Node filesystem failures cross the JS
			// boundary as native exceptions. We contain them as a conservative
			// non-writable directory result, matching upstream's best-effort access check.
		} catch (error:Dynamic) {
			return false;
		}
	}

	static function pickBinary(pkg:String, dir:String, binDir:String):Null<String> {
		final files = readDirectoryNames(binDir);
		if (files.length == 0)
			return null;
		if (files.length == 1)
			return files[0];

		final pkgJson = readJson(NodePath.join(NodePath.join(dir, "node_modules"), NodePath.join(pkg, "package.json")));
		final bin = field(pkgJson, "bin");
		if (bin != null) {
			final unscoped = unscopedName(pkg);
			if (isString(bin))
				return unscoped;
			final keys = objectKeys(bin);
			if (keys.length == 1)
				return keys[0];
			if (hasField(bin, unscoped))
				return unscoped;
			if (keys.length > 0)
				return keys[0];
		}

		return files[0];
	}

	static function readDirectoryNames(dir:String):Array<String> {
		try {
			return Fs.readdirNamesSync(dir);
			// Dynamic is required here because missing cache/bin directories are normal
			// Node filesystem failures. The Npm.which contract treats them as no files.
		} catch (error:Dynamic) {
			return [];
		}
	}

	static function unscopedName(pkg:String):String {
		if (!pkg.startsWith("@"))
			return pkg;
		final pieces = pkg.split("/");
		return pieces.length > 1 ? pieces[1] : pkg;
	}

	static function readJson(path:String):Unknown {
		if (!Fs.existsSync(path))
			return emptyObject();
		try {
			return parseJson(Fs.readFileSync(path, "utf8"));
			// Dynamic is required at this JSON/file boundary because malformed JSON and
			// native filesystem failures are intentionally contained as an empty object.
		} catch (error:Dynamic) {
			return emptyObject();
		}
	}

	static function parseJson(text:String):Unknown {
		try {
			return Unknown.fromBoundary(Json.parse(text));
			// Dynamic is required at this JSON boundary because Json.parse returns
			// untrusted runtime data. The value is immediately wrapped as Unknown and
			// narrowed only through guarded helpers below.
		} catch (error:Dynamic) {
			return emptyObject();
		}
	}

	static function dependencyNames(data:Unknown):Array<String> {
		final out:Array<String> = [];
		for (name in DEPENDENCY_FIELDS) {
			final section = field(data, name);
			if (section == null)
				continue;
			for (key in objectKeys(section))
				pushUnique(out, key);
		}
		return out;
	}

	static function pushUnique(out:Array<String>, value:String):Void {
		if (out.indexOf(value) == -1)
			out.push(value);
	}

	static function emptyObject():Unknown {
		return Unknown.fromBoundary({});
	}

	static function field(data:Unknown, name:String):Null<Unknown> {
		return UnknownAccess.field(data, name);
	}

	static function hasField(data:Unknown, name:String):Bool {
		return UnknownAccess.hasOwnField(data, name);
	}

	static function stringField(data:Unknown, name:String):Null<String> {
		return UnknownAccess.stringField(data, name);
	}

	static function isString(value:Unknown):Bool {
		return UnknownAccess.isString(value);
	}

	static function objectKeys(data:Unknown):Array<String> {
		return UnknownAccess.objectKeys(data);
	}

	static function isRange(version:String):Bool {
		return ~/[\s\^~*xX<>|=]/.match(version);
	}

	static function satisfies(version:String, range:String):Bool {
		for (choice in range.split("||")) {
			if (satisfiesAll(version, choice.trim()))
				return true;
		}
		return false;
	}

	static function satisfiesAll(version:String, range:String):Bool {
		if (range == "" || range == "*" || range.toLowerCase() == "x")
			return true;
		final tokens = nonEmpty(range.split(" "));
		if (tokens.length > 1) {
			for (token in tokens) {
				if (!satisfiesAll(version, token))
					return false;
			}
			return true;
		}

		if (range.startsWith("^")) {
			final base = parseSemver(range.substr(1));
			final current = parseSemver(version);
			if (compareSemver(current, base) < 0)
				return false;
			if (base.major > 0)
				return current.major == base.major;
			if (base.minor > 0)
				return current.major == base.major && current.minor == base.minor;
			return current.major == base.major && current.minor == base.minor && current.patch == base.patch;
		}

		if (range.startsWith("~")) {
			final base = parseSemver(range.substr(1));
			final current = parseSemver(version);
			return compareSemver(current, base) >= 0 && current.major == base.major && current.minor == base.minor;
		}

		return satisfiesComparator(version, range);
	}

	static function satisfiesComparator(version:String, range:String):Bool {
		final current = parseSemver(version);
		if (range.startsWith(">="))
			return compareSemver(current, parseSemver(range.substr(2))) >= 0;
		if (range.startsWith("<="))
			return compareSemver(current, parseSemver(range.substr(2))) <= 0;
		if (range.startsWith(">"))
			return compareSemver(current, parseSemver(range.substr(1))) > 0;
		if (range.startsWith("<"))
			return compareSemver(current, parseSemver(range.substr(1))) < 0;
		if (range.startsWith("="))
			return compareSemver(current, parseSemver(range.substr(1))) == 0;
		if (range.indexOf("x") != -1 || range.indexOf("X") != -1 || range.indexOf("*") != -1)
			return wildcardSatisfies(current, range);
		return compareSemver(current, parseSemver(range)) == 0;
	}

	static function wildcardSatisfies(current:SemverParts, range:String):Bool {
		final pieces = range.split(".");
		if (pieces.length > 0 && isWildcard(pieces[0]))
			return true;
		if (pieces.length > 0 && current.major != parsePart(pieces[0]))
			return false;
		if (pieces.length > 1 && !isWildcard(pieces[1]) && current.minor != parsePart(pieces[1]))
			return false;
		if (pieces.length > 2 && !isWildcard(pieces[2]) && current.patch != parsePart(pieces[2]))
			return false;
		return true;
	}

	static function semverLt(left:String, right:String):Bool {
		return compareSemver(parseSemver(left), parseSemver(right)) < 0;
	}

	static function compareSemver(left:SemverParts, right:SemverParts):Int {
		if (left.major != right.major)
			return left.major < right.major ? -1 : 1;
		if (left.minor != right.minor)
			return left.minor < right.minor ? -1 : 1;
		if (left.patch != right.patch)
			return left.patch < right.patch ? -1 : 1;
		return 0;
	}

	static function parseSemver(version:String):SemverParts {
		var cleaned = version.trim();
		if (cleaned.startsWith("v"))
			cleaned = cleaned.substr(1);
		final pre = cleaned.indexOf("-");
		if (pre != -1)
			cleaned = cleaned.substr(0, pre);
		final build = cleaned.indexOf("+");
		if (build != -1)
			cleaned = cleaned.substr(0, build);
		final parts = cleaned.split(".");
		return {
			major: parts.length > 0 ? parsePart(parts[0]) : 0,
			minor: parts.length > 1 ? parsePart(parts[1]) : 0,
			patch: parts.length > 2 ? parsePart(parts[2]) : 0,
		};
	}

	static function parsePart(part:String):Int {
		final normalized = part.split("-")[0].split("+")[0];
		final parsed = Std.parseInt(normalized);
		return parsed == null ? 0 : parsed;
	}

	static function isWildcard(part:String):Bool {
		final lower = part.toLowerCase();
		return lower == "*" || lower == "x";
	}

	static function nonEmpty(items:Array<String>):Array<String> {
		final out:Array<String> = [];
		for (item in items) {
			final trimmed = item.trim();
			if (trimmed != "")
				out.push(trimmed);
		}
		return out;
	}
}
