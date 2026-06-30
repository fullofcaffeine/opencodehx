package opencodehx.util;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.Json;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;

class ModuleResolver {
	public static function resolve(id:String, dir:String):Null<String> {
		final parsed = parse(id);
		var current = NodePath.resolve(dir, ".");
		while (true) {
			final packageRoot = NodePath.join(NodePath.join(current, "node_modules"), parsed.name);
			if (Fs.existsSync(packageRoot) && Fs.statSync(packageRoot).isDirectory()) {
				final resolved = resolveInPackage(packageRoot, parsed.subpath);
				if (resolved != null)
					return resolved;
			}
			final parent = NodePath.dirname(current);
			if (parent == current)
				break;
			current = parent;
		}
		return null;
	}

	static function resolveInPackage(root:String, subpath:String):Null<String> {
		if (subpath != "")
			return resolveFile(NodePath.join(root, subpath));
		final pkg = NodePath.join(root, "package.json");
		if (Fs.existsSync(pkg)) {
			final value = UnknownNarrow.record(Unknown.fromBoundary(Json.parse(Fs.readFileSync(pkg, "utf8"))));
			final main = value == null ? null : UnknownNarrow.string(value.get("main"));
			if (main != null) {
				final resolved = resolveFile(NodePath.join(root, main));
				if (resolved != null)
					return resolved;
			}
		}
		return resolveFile(NodePath.join(root, "index.js"));
	}

	static function resolveFile(path:String):Null<String> {
		if (isFile(path))
			return path;
		for (ext in [".js", ".json", ".node"]) {
			if (isFile(path + ext))
				return path + ext;
		}
		final index = NodePath.join(path, "index.js");
		return isFile(index) ? index : null;
	}

	static function isFile(path:String):Bool {
		return Fs.existsSync(path) && Fs.statSync(path).isFile();
	}

	static function parse(id:String):ModuleResolveInput {
		final parts = id.split("/");
		if (StringTools.startsWith(id, "@") && parts.length >= 2) {
			return {
				name: parts[0] + "/" + parts[1],
				subpath: parts.slice(2).join("/")
			};
		}
		return {
			name: parts[0],
			subpath: parts.slice(1).join("/")
		};
	}
}

typedef ModuleResolveInput = {
	final name:String;
	final subpath:String;
}
