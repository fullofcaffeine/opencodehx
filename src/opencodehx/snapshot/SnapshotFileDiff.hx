package opencodehx.snapshot;

/**
 * Upstream-shaped snapshot file diff stored in session summaries and exports.
 *
 * Keep this DTO separate from `SnapshotRuntime` so macro/codegen paths can
 * reference the data shape without importing Node-backed runtime seams.
 */
typedef SnapshotFileDiff = {
	final file:String;
	final patch:String;
	final additions:Int;
	final deletions:Int;
	final status:String;
}
