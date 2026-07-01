package opencodehx.config;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.util.Compare.compareString;

class ConfigMarkdownFiles {
	public static function scan(dir:String, roots:Array<String>, recursive:Bool = true):Array<String> {
		final result:Array<String> = [];
		for (root in roots) {
			final base = NodePath.join(dir, root);
			if (Fs.existsSync(base))
				walk(base, recursive, result);
		}
		result.sort(compareString);
		return result;
	}

	static function walk(dir:String, recursive:Bool, result:Array<String>):Void {
		for (name in Fs.readdirNamesSync(dir)) {
			final absolute = NodePath.join(dir, name);
			final stat = Fs.statSync(absolute);
			if (stat.isDirectory()) {
				if (recursive)
					walk(absolute, recursive, result);
				continue;
			}
			if (stat.isFile() && StringTools.endsWith(name, ".md"))
				result.push(absolute);
		}
	}
}
