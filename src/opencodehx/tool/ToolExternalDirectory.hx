package opencodehx.tool;

import opencodehx.file.FileSystem;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolTypes.KnownToolID;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolPermissionMetadata;

/**
	Shared external-directory permission shape for tools that may operate outside
	the active project directory.

	Each caller still owns its normal file/search behavior. This helper only
	normalizes the upstream permission request: inside-project targets are silent;
	outside file targets ask for the parent `dir/*`; outside directory targets ask
	for the directory's own `dir/*`.
**/
enum ExternalDirectoryKind {
	ExternalFile;
	ExternalDirectory;
}

function requireExternalDirectory(owner:KnownToolID, ctx:ToolContext, target:String, kind:ExternalDirectoryKind):Void {
	final full = NodePath.resolve(target, ".");
	if (FileSystem.contains(ctx.directory, full))
		return;

	final parentDir = switch kind {
		case ExternalFile:
			NodePath.dirname(full);
		case ExternalDirectory:
			full;
	}
	final pattern = ToolPaths.normalize(NodePath.join(parentDir, "*"));
	ToolPermission.require(owner, ctx, {
		permission: "external_directory",
		patterns: [pattern],
		always: [pattern],
		metadata: ToolPermissionMetadata.checked({
			filepath: full,
			parentDir: parentDir,
		})
	});
}
