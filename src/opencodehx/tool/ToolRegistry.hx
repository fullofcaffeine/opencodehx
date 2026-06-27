package opencodehx.tool;

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

	public function register(def:ToolDef):Void {
		byId.set(def.id, def);
	}

	public function ids():Array<String> {
		final result:Array<String> = [];
		for (id in byId.keys())
			result.push(id);
		result.sort(Reflect.compare);
		return result;
	}

	public function all(?filter:ToolFilter):Array<ToolDef> {
		final disabled = filter == null || filter.disabled == null ? [] : filter.disabled;
		final result:Array<ToolDef> = [];
		for (id in ids()) {
			if (disabled.indexOf(id) == -1)
				result.push(byId.get(id));
		}
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
}
