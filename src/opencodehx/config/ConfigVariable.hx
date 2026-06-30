package opencodehx.config;

import opencodehx.config.ConfigLoader.ConfigEnv;
import opencodehx.config.ConfigError.ConfigException;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;

typedef VariableContext = {
	final dir:String;
	@:optional final env:ConfigEnv;
}

class ConfigVariable {
	public static function substitute(text:String, ctx:VariableContext):String {
		final out = new StringBuf();
		var i = 0;
		while (i < text.length) {
			if (startsWithAt(text, "{env:", i)) {
				final end = text.indexOf("}", i + 5);
				if (end != -1) {
					final key = text.substr(i + 5, end - i - 5);
					out.add(envValue(ctx, key));
					i = end + 1;
					continue;
				}
			}
			if (startsWithAt(text, "{file:", i)) {
				final end = text.indexOf("}", i + 6);
				if (end != -1) {
					final file = text.substr(i + 6, end - i - 6);
					out.add(readIncludedFile(ctx.dir, file));
					i = end + 1;
					continue;
				}
			}
			out.add(text.charAt(i));
			i++;
		}
		return out.toString();
	}

	static function envValue(ctx:VariableContext, key:String):String {
		if (ctx.env != null) {
			final value = ctx.env.value(key);
			return value == null ? "" : value;
		}
		final value = NodeProcess.envValue(key);
		return value == null ? "" : value;
	}

	static function readIncludedFile(dir:String, file:String):String {
		final path = NodePath.isAbsolute(file) ? file : NodePath.join(dir, file);
		try {
			return Fs.readFileSync(path, "utf8");
		} catch (error:Dynamic) {
			throw new ConfigException(IoError(path, Std.string(error)));
		}
	}

	static function startsWithAt(text:String, needle:String, index:Int):Bool {
		return text.substr(index, needle.length) == needle;
	}
}
