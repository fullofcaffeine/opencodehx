#!/usr/bin/env node

import path from "node:path";
import ts from "typescript";
import { rootPath } from "../harness/paths.mjs";

/**
 * Strict-checks declaration diagnostics owned by classic OpenCodeHX output.
 *
 * Why: the same-source classic profile emits a large `.d.ts` graph that names
 * real npm APIs. `skipLibCheck: true` would also hide compiler defects in our
 * generated files, while failing on every transitive package declaration would
 * make this profile responsible for unrelated AI SDK release debt.
 *
 * What: TypeScript still builds one program with `skipLibCheck: false`. Every
 * diagnostic located in `classic-dist`, the checked-in `types` boundary, or
 * global/config space is blocking. Diagnostics whose source file is owned by a
 * dependency are counted separately and remain the dependency's contract.
 *
 * How: ownership is classified from canonical filesystem paths after the full
 * Compiler API diagnostic pass. No diagnostic text or error code is
 * allowlisted, so a new generated declaration failure cannot disappear behind
 * a package-specific exception. The default genes-ts build remains the primary
 * strict implementation/typecheck surface for the complete application.
 */

const configPath = rootPath("tsconfig.classic.json");
const classicRoot = rootPath("classic-dist");
const checkedTypesRoot = rootPath("types");

const config = ts.readConfigFile(configPath, ts.sys.readFile);
if (config.error !== undefined) {
	fail([config.error]);
}

const parsed = ts.parseJsonConfigFileContent(
	config.config,
	ts.sys,
	path.dirname(configPath),
	undefined,
	configPath,
);
if (parsed.errors.length > 0) {
	fail(parsed.errors);
}

const program = ts.createProgram({
	rootNames: parsed.fileNames,
	options: parsed.options,
	projectReferences: parsed.projectReferences,
});
const diagnostics = ts.getPreEmitDiagnostics(program);
const owned = diagnostics.filter((diagnostic) => isOwned(diagnostic.file?.fileName));
const dependencyOwned = diagnostics.length - owned.length;

if (owned.length > 0) {
	fail(owned);
}

console.log(
	`classic-declarations:ok (${parsed.fileNames.length} roots; ${dependencyOwned} dependency-owned diagnostics nonblocking)`,
);

function isOwned(fileName) {
	if (fileName === undefined) return true;
	return isWithin(classicRoot, fileName) || isWithin(checkedTypesRoot, fileName);
}

function isWithin(root, candidate) {
	const relative = path.relative(root, path.resolve(candidate));
	return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function fail(diagnostics) {
	console.error(
		ts.formatDiagnosticsWithColorAndContext(diagnostics, {
			getCanonicalFileName: (fileName) => fileName,
			getCurrentDirectory: () => rootPath(),
			getNewLine: () => ts.sys.newLine,
		}),
	);
	process.exit(1);
}
