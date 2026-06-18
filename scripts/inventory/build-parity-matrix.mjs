#!/usr/bin/env node
import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs"
import { dirname, join, relative } from "node:path"

const repoRoot = new URL("../..", import.meta.url).pathname
const upstreamRoot = join(repoRoot, "..", "opencode", "packages", "opencode")
const sourceRoot = join(upstreamRoot, "src")
const testRoot = join(upstreamRoot, "test")

function walk(root) {
  const out = []
  function visit(dir) {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name)
      const stat = statSync(path)
      if (stat.isDirectory()) visit(path)
      else if (stat.isFile()) out.push(path)
    }
  }
  visit(root)
  return out.sort()
}

function read(path) {
  return readFileSync(path, "utf8")
}

function csv(value) {
  const text = String(value ?? "")
  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text
}

function writeCsv(path, rows) {
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, rows.map((row) => row.map(csv).join(",")).join("\n") + "\n")
}

function firstSegment(path) {
  return path.includes("/") ? path.split("/")[0] : "root"
}

function areaFor(path) {
  const segment = firstSegment(path)
  if (path.startsWith("cli/tui/")) return "tui"
  if (segment === "v2") return "session"
  return segment
}

function runtimeClass(path, content) {
  if (path.endsWith(".tsx")) return "tsx"
  if (path.includes(".bun.")) return "bun-host"
  if (path.includes(".node.")) return "node-host"
  if (path.includes("/prompt/") || path.includes("/template/")) return "resource"
  if (/\bfrom\s+["']node:|\bimport\(["']node:/.test(content)) return "node-host"
  if (/\bBun\./.test(content)) return "bun-host"
  if (/\bfrom\s+["']solid-js|\bfrom\s+["']@opentui\//.test(content)) return "tsx"
  if (/\bfrom\s+["']hono\b|\bWebSocket\b|\bEventSource\b|\bReadableStream\b/.test(content)) return "node-host"
  return "portable"
}

function externNeeds(content) {
  const imports = new Set()
  const patterns = [
    /^\s*(?:import|export)\b[\s\S]*?\bfrom\s+["']([^"'\n]+)["']/gm,
    /\bimport\s*\(\s*["']([^"'\n]+)["']\s*\)/g,
    /\brequire\s*\(\s*["']([^"'\n]+)["']\s*\)/g,
  ]
  for (const pattern of patterns) {
    for (const match of content.matchAll(pattern)) {
      const spec = match[1]
      if (!spec.startsWith(".") && !spec.startsWith("#") && !spec.startsWith("@/")) imports.add(spec)
    }
  }
  return [...imports].sort().join("; ")
}

function genesRisks(path, content) {
  const risks = []
  if (path.endsWith(".tsx")) risks.push("tsx")
  if (/\bimport\s*\(/.test(content)) risks.push("dynamic-import")
  if (/\bfrom\s+["']node:|\bimport\(["']node:/.test(content)) risks.push("node-builtins")
  if (path.includes(".bun.") || /\bBun\./.test(content)) risks.push("bun-api")
  if (/\bfrom\s+["']effect\b|\bEffect\./.test(content)) risks.push("effect")
  if (/\bfrom\s+["']zod\b|\bz\./.test(content)) risks.push("zod")
  if (/\bReadableStream\b|\bAsyncIterable\b|\bEventSource\b|\bWebSocket\b/.test(content)) risks.push("streams")
  if (/\bfrom\s+["'][^"']+\.(json|txt|md)["']/.test(content)) risks.push("resource-import")
  if (/\btype\s+\w+\s*=.*\|/.test(content)) risks.push("ts-union")
  return risks.length ? risks.join("; ") : "none"
}

function portPriority(area, runtime, path) {
  if (["util", "format", "id", "flag", "env", "file", "config"].includes(area)) return "P0"
  if (area === "session" && /message|system|prompt|index|state|share/.test(path)) return "P0"
  if (["permission", "tool", "storage", "provider", "cli"].includes(area)) return "P1"
  if (["server", "shell", "pty", "lsp", "mcp", "acp", "plugin"].includes(area)) return "P2"
  if (runtime === "tsx" || area === "tui") return "P2"
  if (["control-plane", "installation", "sync", "share"].includes(area)) return "P3"
  return "P2"
}

function lineCount(content) {
  return content.length === 0 ? 0 : content.split(/\r?\n/).length
}

function oracleFor(area, testsByArea) {
  const tests = testsByArea.get(area) ?? []
  if (!tests.length) return "no direct upstream test mapped"
  return tests.slice(0, 4).join("; ") + (tests.length > 4 ? `; +${tests.length - 4} more` : "")
}

function testPriority(path) {
  const area = areaFor(path)
  if (["config", "file", "tool", "session", "provider", "storage"].includes(area)) return "P0"
  if (["server", "permission", "shell", "pty", "lsp", "mcp", "plugin", "cli"].includes(area)) return "P1"
  if (path.endsWith(".tsx") || path.includes("/tui/")) return "P2"
  return "P2"
}

const testFiles = walk(testRoot).map((path) => relative(testRoot, path))
const testsByArea = new Map()
for (const testPath of testFiles) {
  const area = areaFor(testPath)
  const existing = testsByArea.get(area) ?? []
  existing.push(testPath)
  testsByArea.set(area, existing)
}

const sourceRows = [[
  "source_path",
  "area",
  "runtime_class",
  "loc",
  "extern_needs",
  "genes_ts_risks",
  "test_oracle",
  "port_priority",
  "acceptance_gate",
]]

const areaSummary = new Map()
for (const file of walk(sourceRoot)) {
  const sourcePath = relative(sourceRoot, file)
  const content = read(file)
  const area = areaFor(sourcePath)
  const runtime = runtimeClass(sourcePath, content)
  const priority = portPriority(area, runtime, sourcePath)
  const summary = areaSummary.get(area) ?? { files: 0, loc: 0, priorities: new Map(), runtimes: new Map() }
  summary.files += 1
  summary.loc += lineCount(content)
  summary.priorities.set(priority, (summary.priorities.get(priority) ?? 0) + 1)
  summary.runtimes.set(runtime, (summary.runtimes.get(runtime) ?? 0) + 1)
  areaSummary.set(area, summary)
  sourceRows.push([
    sourcePath,
    area,
    runtime,
    lineCount(content),
    externNeeds(content) || "none",
    genesRisks(sourcePath, content),
    oracleFor(area, testsByArea),
    priority,
    `port ${area} slice; compare against mapped upstream tests/fixtures`,
  ])
}

const testRows = [["test_path", "area", "priority", "oracle_role"]]
for (const testPath of testFiles) {
  const area = areaFor(testPath)
  testRows.push([testPath, area, testPriority(testPath), `oracle for ${area}`])
}

writeCsv(join(repoRoot, "reference", "opencode-source-parity-matrix.csv"), sourceRows)
writeCsv(join(repoRoot, "reference", "opencode-test-priority-matrix.csv"), testRows)

const summaryRows = [...areaSummary.entries()].sort((a, b) => a[0].localeCompare(b[0]))
const totalFiles = sourceRows.length - 1
const totalTests = testRows.length - 1
const totalLoc = summaryRows.reduce((sum, [, entry]) => sum + entry.loc, 0)

const markdown = [
  "# OpenCode Source Inventory And Parity Matrix",
  "",
  "**Bead:** `opencodehx-001`",
  "",
  "## Summary",
  "",
  `- Upstream source root: \`${relative(repoRoot, sourceRoot)}\``,
  `- Source files inventoried: ${totalFiles}`,
  `- Approximate source LOC: ${totalLoc}`,
  `- Upstream test files inventoried: ${totalTests}`,
  `- Full source matrix: \`reference/opencode-source-parity-matrix.csv\``,
  `- Test priority matrix: \`reference/opencode-test-priority-matrix.csv\``,
  "",
  "## Area Summary",
  "",
  "| Area | Files | LOC | Runtime classes | Port priorities |",
  "| --- | ---: | ---: | --- | --- |",
  ...summaryRows.map(([area, entry]) => {
    const runtimes = [...entry.runtimes.entries()].map(([key, count]) => `${key}:${count}`).join("; ")
    const priorities = [...entry.priorities.entries()].sort().map(([key, count]) => `${key}:${count}`).join("; ")
    return `| ${area} | ${entry.files} | ${entry.loc} | ${runtimes} | ${priorities} |`
  }),
  "",
  "## Classification Rules",
  "",
  "- **Area** is mostly the first source/test path segment, with `cli/tui` grouped as `tui` and `v2` grouped into `session`.",
  "- **Runtime class** is heuristic: `.tsx` and Solid/OpenTUI imports are `tsx`; `.bun.*` and Bun APIs are `bun-host`; `.node.*` and Node built-ins are `node-host`; prompts/templates are `resource`; the rest starts as `portable`.",
  "- **Extern needs** are non-relative import specifiers extracted from static and dynamic imports.",
  "- **genes-ts risks** flag TSX, dynamic imports, Node built-ins, Bun APIs, Effect/Zod usage, streams, resource imports, and obvious TS unions.",
  "- **Port priority** favors pure/config/file/session DTO foundations first, then tools/providers/storage/CLI, then server/protocol/TUI/plugin surfaces.",
  "",
  "This is a first-pass planning matrix, not a semantic proof. Refine rows as each slice is ported and tested.",
  "",
].join("\n")

writeFileSync(join(repoRoot, "docs", "opencode-source-inventory.md"), markdown)
