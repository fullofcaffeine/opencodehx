package opencodehx.agent;

import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.AgentInfo;

class AgentRuntime {
	final config:ConfigInfo;

	public function new(config:ConfigInfo) {
		this.config = config;
	}

	public function get(name:String):Null<AgentInfo> {
		final agents = config.agent;
		return agents == null ? null : agents.get(name);
	}
}
