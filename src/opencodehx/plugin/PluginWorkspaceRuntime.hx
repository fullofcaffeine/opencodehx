package opencodehx.plugin;

import opencodehx.controlplane.WorkspaceAdaptors;
import opencodehx.controlplane.WorkspaceAdaptors.WorkspaceAdaptor;
import opencodehx.project.ProjectRuntime.ProjectID;

typedef PluginWorkspaceRegistry = {
	final register:(String, WorkspaceAdaptor) -> Void;
}

class PluginWorkspaceRuntime {
	public static function registry(projectID:ProjectID):PluginWorkspaceRegistry {
		return {
			// Workspace adaptor type strings are plugin-defined boundary data.
			register: (type, adaptor) -> WorkspaceAdaptors.register(projectID, type, adaptor),
		};
	}
}
