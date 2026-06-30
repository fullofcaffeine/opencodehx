package opencodehx.tool;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolResult;

typedef ToolFilter = {
	@:optional final disabled:Array<String>;
}

class ToolRegistry {
	final byId = new Map<String, ToolDef>();

	public function new(?defs:Array<ToolDef>) {
		final list = defs == null ? builtin() : defs;
		for (def in list)
			register(def);
	}

	public static function builtin():Array<ToolDef> {
		return [
			ApplyPatchTool.define(),
			BashTool.define(),
			EditTool.define(),
			GlobTool.define(),
			GrepTool.define(),
			InvalidTool.define(),
			ReadTool.define(),
			WriteTool.define()
		];
	}

	public static function withProjectCustomTools(directory:String, ?defs:Array<ToolDef>):ToolRegistry {
		final registry = new ToolRegistry(defs);
		for (def in discoverProjectCustomTools(directory))
			registry.register(def);
		return registry;
	}

	public static function discoverProjectCustomTools(directory:String):Array<ToolDef> {
		final config = NodePath.join(directory, ".opencode");
		final result:Array<ToolDef> = [];
		for (folder in ["tool", "tools"]) {
			final dir = NodePath.join(config, folder);
			if (!Fs.existsSync(dir))
				continue;
			for (entry in Fs.readdirDirentsSync(dir, {withFileTypes: true})) {
				if (!entry.isFile())
					continue;
				final ext = NodePath.extname(entry.name);
				if (ext != ".js" && ext != ".ts")
					continue;
				result.push(customFileDef(toolIDFromFilename(entry.name)));
			}
		}
		return result;
	}

	public function register(def:ToolDef):Void {
		byId.set(def.id, def);
	}

	public function ids(?filter:ToolFilter):Array<String> {
		final disabled = filter == null || filter.disabled == null ? [] : filter.disabled;
		final result:Array<String> = [];
		for (id in byId.keys()) {
			if (disabled.indexOf(id) == -1)
				result.push(id);
		}
		result.sort((a, b) -> {
			if (a < b)
				return -1;
			if (a > b)
				return 1;
			return 0;
		});
		return result;
	}

	public function all(?filter:ToolFilter):Array<ToolDef> {
		final result:Array<ToolDef> = [];
		for (id in ids(filter))
			result.push(byId.get(id));
		return result;
	}

	public function get(id:String, ?filter:ToolFilter):ToolDef {
		if (!byId.exists(id))
			throw new ToolException(UnknownTool(id));
		if (filter != null && filter.disabled != null && filter.disabled.indexOf(id) != -1)
			throw new ToolException(DisabledTool(id));
		return byId.get(id);
	}

	public function execute(id:String, args:ToolCallInput, ctx:ToolContext, ?filter:ToolFilter):ToolResult {
		final def = get(id, filter);
		return def.execute(args, ctx);
	}

	static function toolIDFromFilename(name:String):String {
		final ext = NodePath.extname(name);
		return name.substr(0, name.length - ext.length);
	}

	static function customFileDef(id:String):ToolDef {
		return {
			id: id,
			description: 'Custom tool "${id}" discovered from project config.',
			schema: {parameters: []},
			execute: (_, _) -> {
				throw new ToolException(ExecutionFailed(id, "Custom tool module execution is deferred until plugin-style dynamic loading is ported."));
			},
		};
	}
}
