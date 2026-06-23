import fs from "node:fs";
import path from "node:path";

const sourceRoot = path.join("src", "opencodehx");
const outputPath = path.join("reference", "portability-classification-ledger.csv");

const files = [];
walk(sourceRoot);
files.sort();

const rows = files.map(classify);
fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, toCsv(rows));

const counts = new Map();
for (const row of rows) counts.set(row.primaryClass, (counts.get(row.primaryClass) ?? 0) + 1);
console.log(`Wrote ${rows.length} Haxe file classifications to ${outputPath}`);
for (const [name, count] of [...counts.entries()].sort()) {
  console.log(`${name}: ${count}`);
}

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const file = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(file);
      continue;
    }
    if (file.endsWith(".hx")) files.push(file);
  }
}

function classify(file) {
  const relative = file.split(path.sep).join("/").replace(/^src\/opencodehx\//, "");
  const text = fs.readFileSync(file, "utf8");
  const secondary = new Set();
  const blockers = new Set();
  let primaryClass = "portable";
  let notes = "Haxe domain/model code; retarget after replacing any listed secondary seams.";

  if (relative.startsWith("smoke/") || relative.startsWith("harness/") || relative === "fixtures/DynamicFixture.hx") {
    primaryClass = "harness";
    notes = "Executable parity/test harness; portability target is generated test intent, not product runtime.";
  } else if (
    relative.startsWith("externs/node/") ||
    relative.startsWith("host/node/") ||
    relative === "git/Git.hx" ||
    relative === "pty/PtyService.hx" ||
    relative === "storage/SqliteSessionStore.hx"
  ) {
    primaryClass = "node-host";
    notes = "Node-specific host or extern seam; retarget by replacing this adapter behind the existing Haxe-facing API.";
  } else if (relative.startsWith("externs/web/") || relative.startsWith("externs/ws/")) {
    primaryClass = "web-host";
    notes = "Web platform extern seam; Rust/Go need native HTTP/stream/WebSocket adapters or generated bindings.";
  } else if (relative.startsWith("externs/")) {
    primaryClass = "npm-extern";
    notes = "TypeScript/npm extern declaration; retarget by swapping package integration or preserving it behind a TS adapter.";
  } else if (relative.startsWith("resource/")) {
    primaryClass = "resource";
    notes = "Generated/copied resource manifest seam; retarget needs a target-native asset packaging story.";
  } else if (relative.startsWith("tui/")) {
    primaryClass = relative === "tui/TuiScaffold.hx" ? "tsx" : "portable";
    notes =
      relative === "tui/TuiScaffold.hx"
        ? "TSX/OpenTUI scaffold surface; retarget requires a new renderer adapter."
        : "TUI model/helper code; portable once renderer and resource seams are replaced.";
  } else if (
    relative === "Main.hx" ||
    relative.startsWith("cli/") ||
    relative.startsWith("server/") ||
    relative.startsWith("sync/Workspace") ||
    relative.startsWith("file/FileWatcher") ||
    relative === "file/Ripgrep.hx" ||
    relative === "file/FileSystem.hx" ||
    relative === "npm/Npm.hx" ||
    relative.startsWith("installation/")
  ) {
    primaryClass = "node-host";
    notes =
      "Application logic currently crosses Node process/filesystem/network/package-manager seams; split or retarget those host adapters first.";
  }

  if (/opencodehx\.externs\.node|opencodehx\.host\.node|node:/.test(text)) secondary.add("node-host");
  if (/opencodehx\.externs\.web|opencodehx\.externs\.ws|GlobalFetch|ReadableStream|WebSocket/.test(text)) secondary.add("web-host");
  if (/opencodehx\.externs\.(ai|aws|better_sqlite3|effect|hono|jsonc|opentui|toml|treesitter)/.test(text)) secondary.add("npm-extern");
  if (/genes\.ts|@:ts\.|tsx|jsx\(/.test(text)) secondary.add("generated-ts-only");
  if (/js\.Syntax|untyped/.test(text)) secondary.add("raw-js-boundary");
  if (/js\.lib\.(Promise|Error|Uint8Array|ArrayBuffer)|js\.html/.test(text)) secondary.add("js-runtime");
  if (/\bDynamic\b|\bUnknown\b|UnknownNarrow\b/.test(text)) secondary.add("unknown-boundary");
  if (/Fs\.|NodePath\.|NodeProcess\.|ChildProcess\.|Process\.|Os\.|Crypto\.|NodeBuffer\./.test(text)) secondary.add("node-api");
  if (/AiSdk|LanguageModel|streamText|embed|providerOptions/.test(text)) secondary.add("ai-sdk");
  if (/Hono|NodeHono|ServerWebSocket|WebSocket/.test(text)) secondary.add("server-runtime");
  if (/better_sqlite3|Sqlite|Database/.test(text)) secondary.add("sqlite");
  if (/^resource\//.test(relative) || /Resources\./.test(text)) secondary.add("resource");

  if (/Promise/.test(text)) blockers.add("Promise/async lowering");
  if (/opencodehx\.externs\.node|opencodehx\.host\.node|Fs\.|NodeProcess\.|ChildProcess\./.test(text)) blockers.add("Node API adapter");
  if (/opencodehx\.externs\.(ai|aws|better_sqlite3|hono|opentui|treesitter)/.test(text)) blockers.add("npm package adapter");
  if (/genes\.ts|@:ts\./.test(text)) blockers.add("genes-ts-only type surface");
  if (/js\.Syntax|untyped/.test(text)) blockers.add("raw JS expression");
  if (/\bDynamic\b|\bUnknown\b/.test(text)) blockers.add("runtime unknown boundary");

  if (primaryClass === "portable" && secondary.has("node-host")) primaryClass = "node-host";
  if (primaryClass === "portable" && secondary.has("npm-extern")) primaryClass = "npm-extern";
  if (primaryClass === "portable" && secondary.has("web-host")) primaryClass = "web-host";
  if (primaryClass === "portable" && secondary.has("generated-ts-only")) primaryClass = "generated-ts-only";

  return {
    path: `src/opencodehx/${relative}`,
    primaryClass,
    secondaryClasses: [...secondary].sort().filter((item) => item !== primaryClass).join(";") || "none",
    retargetBlockers: [...blockers].join(";") || "none",
    notes,
  };
}

function toCsv(rows) {
  return [
    "path,primary_class,secondary_classes,retarget_blockers,notes",
    ...rows.map((row) =>
      [row.path, row.primaryClass, row.secondaryClasses, row.retargetBlockers, row.notes].map((value) => `"${String(value).replaceAll('"', '""')}"`).join(","),
    ),
  ].join("\n") + "\n";
}
