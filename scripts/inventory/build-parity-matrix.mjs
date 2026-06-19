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
  if (path === "keybind.test.ts") return "tui"
  if (path === "permission-task.test.ts") return "permission"
  if (path === "npm.test.ts") return "installation"
  if (path === "preload.ts") return "root"
  if (segment === "v2") return "session"
  if (segment === "filesystem") return "file"
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

function testKind(path) {
  if (/\.test\.tsx?$/.test(path)) return "test"
  if (path.includes("__snapshots__/")) return "snapshot"
  if (path === "AGENTS.md" || path.endsWith(".md")) return "doc"
  if (path.includes("/fixtures/") || path.startsWith("fixture/") || path.startsWith("fake/")) return "fixture"
  if (path.startsWith("lib/") || path === "preload.ts") return "helper"
  return "fixture"
}

function nextBeadFor(path, area) {
  if (path.includes("/tui/") || area === "tui") return "opencodehx-031/opencodehx-032/opencodehx-033/opencodehx-034/opencodehx-035"
  if (area === "server" || area === "control-plane") return "opencodehx-026/opencodehx-027"
  if (area === "session") return "opencodehx-023/opencodehx-048"
  if (area === "provider" || area === "account" || area === "auth") return "opencodehx-024/opencodehx-025"
  if (area === "tool" || area === "patch" || area === "snapshot") return "opencodehx-u5i"
  if (area === "shell" || area === "pty") return "opencodehx-3qi"
  if (area === "permission") return "opencodehx-049"
  if (area === "config") return "opencodehx-zr1"
  if (area === "project" || area === "workspace" || area === "git" || area === "installation" || area === "sync")
    return "opencodehx-who"
  if (area === "mcp" || area === "acp") return "opencodehx-028"
  if (area === "lsp" || area === "ide") return "opencodehx-029"
  if (area === "plugin" || area === "skill") return "opencodehx-030"
  if (area === "cli") return "opencodehx-036"
  if (area === "storage") return "opencodehx-048"
  if (area === "format") return "opencodehx-bvh"
  if (area === "effect" || area === "bus") return "opencodehx-026"
  if (area === "agent" || area === "question") return "opencodehx-023/opencodehx-024"
  if (area === "memory") return "opencodehx-049"
  return "opencodehx-000"
}

function directEvidence(path) {
  const exact = new Map([
    ["util/format.test.ts", ["ported", "src/opencodehx/smoke/UtilSmoke.hx#formatDuration; docs/util-port.md", "none", "UtilSmoke.formatDuration"]],
    ["util/lazy.test.ts", ["ported", "src/opencodehx/smoke/UtilSmoke.hx#lazy; docs/util-port.md", "none", "UtilSmoke.lazy"]],
    ["util/data-url.test.ts", ["ported", "src/opencodehx/smoke/UtilSmoke.hx#dataUrl; docs/util-port.md", "none", "UtilSmoke.dataUrl"]],
    ["fake/provider.ts", ["ported", "src/opencodehx/provider/FakeProvider.hx; scripts/harness/transcript-parity.mjs; docs/fake-provider-transcript-harness.md", "none", "FakeProvider plus one-turn golden transcript"]],
    ["session/message-v2.test.ts", ["partial", "src/opencodehx/smoke/MessageSmoke.hx; docs/message-v2-port.md", "model-message conversion and provider-transform cases are not ported yet", "MessageSmoke codec/part/cursor fixtures"]],
    ["session/processor-effect.test.ts", ["partial", "src/opencodehx/smoke/SessionProcessorSmoke.hx; docs/session-processor-one-turn.md", "current processor is one-turn and synchronous; upstream Effect streaming lifecycle remains deferred", "SessionProcessorSmoke"]],
    ["session/llm.test.ts", ["partial", "fixtures/transcripts/one-turn.golden.json; scripts/harness/transcript-parity.mjs", "real model/provider streaming and tool-call variants remain deferred", "one-turn fake-provider transcript golden"]],
    ["storage/storage.test.ts", ["partial", "src/opencodehx/smoke/StorageSmoke.hx; docs/storage-port.md", "storage service integration beyond session/message CRUD remains deferred", "StorageSmoke"]],
    ["storage/db.test.ts", ["partial", "src/opencodehx/smoke/StorageSmoke.hx; docs/storage-port.md", "Drizzle/node:sqlite parity is represented by the current better-sqlite3 host seam only", "StorageSmoke"]],
    ["config/config.test.ts", ["partial", "src/opencodehx/smoke/ConfigSmoke.hx; docs/config-port.md", "real account repo/service integration, runtime plugin loading/path resolution, and live package-manager dependency install side effects remain deferred; deterministic dependency bootstrap gitignore/install success/failure is covered", "ConfigSmoke"]],
    ["skill/skill.test.ts", ["partial", "src/opencodehx/smoke/SkillSmoke.hx; docs/skill-registry-port.md", "Effect service integration and binary remote skill resources remain deferred", "SkillRegistry local/remote discovery and availability smoke"]],
    ["skill/discovery.test.ts", ["partial", "src/opencodehx/smoke/SkillSmoke.hx; docs/skill-registry-port.md", "Effect service integration and binary remote skill resources remain deferred", "SkillRemoteDiscovery cache/download smoke"]],
    ["session/system.test.ts", ["partial", "src/opencodehx/smoke/SkillSmoke.hx; docs/skill-registry-port.md", "full SystemPrompt service integration remains deferred", "SkillRegistry sorted verbose and permission-filtered availability smoke"]],
    ["file/ignore.test.ts", ["partial", "src/opencodehx/smoke/FileSmoke.hx; docs/file-port.md", "only initial ignore defaults/whitelist behavior is covered", "FileSmoke.ignoreRules"]],
    ["file/ripgrep.test.ts", ["partial", "src/opencodehx/smoke/FileSmoke.hx; docs/file-port.md", "streaming and full ripgrep option matrix remain deferred", "FileSmoke.ripgrepFiles/ripgrepSearch"]],
    ["file/path-traversal.test.ts", ["partial", "src/opencodehx/smoke/FileSmoke.hx; docs/file-port.md", "representative escape checks are covered; full upstream error shape remains deferred", "FileSmoke.pathSafety"]],
    ["tool/glob.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/tool-registry-port.md", "core glob cases are covered; full Effect/tool context parity remains deferred", "ToolSmoke.globExec"]],
    ["tool/grep.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/tool-registry-port.md", "core grep cases are covered; full upstream option matrix remains deferred", "ToolSmoke.grepExec"]],
    ["tool/read.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/core-file-tools-port.md", "representative read file/directory/error behavior is covered; full output/error matrix remains deferred", "ToolSmoke.readExec"]],
    ["tool/write.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/core-file-tools-port.md", "basic write behavior is covered; full overwrite and diagnostics matrix remains deferred", "ToolSmoke.writeExec"]],
    ["tool/edit.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/core-file-tools-port.md", "representative exact/replace-all/multiple-match and tolerant fallback behavior is covered; full upstream Effect/LSP/BOM/event matrix remains deferred", "ToolSmoke.editExec"]],
    ["tool/apply_patch.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/core-file-tools-port.md", "representative add/update/delete/move, EOF, heredoc, Unicode, malformed, and no-side-effect behavior is covered; full upstream Effect/LSP/BOM/event matrix remains deferred", "ToolSmoke.applyPatchExec"]],
    ["tool/bash.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/bash-shell-seam.md", "non-interactive Node shell seam is covered; PTY and tree-sitter scanner remain deferred", "ToolSmoke.bashExec"]],
    ["tool/external-directory.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/bash-shell-seam.md", "external workdir denial is covered for bash; full permission surface remains deferred", "ToolSmoke.bashExec external directory case"]],
    ["tool/registry.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/tool-registry-port.md", "builtin registry and errors are covered; .opencode custom tool loading remains deferred", "ToolSmoke.registrySurface"]],
    ["permission/next.test.ts", ["partial", "src/opencodehx/smoke/PermissionSmoke.hx; docs/permission-model-port.md", "sync ask/allow/deny is covered; full async session prompt lifecycle remains deferred", "PermissionSmoke.runtimeAskReply/toolIntegration"]],
    ["permission/arity.test.ts", ["partial", "src/opencodehx/smoke/PermissionSmoke.hx; docs/permission-model-port.md", "disabled-tool derivation and rule matching are covered; full arity policy remains deferred", "PermissionSmoke.disabledTools"]],
    ["provider/provider.test.ts", ["partial", "src/opencodehx/smoke/ProviderSmoke.hx; docs/provider-registry-port.md", "AI SDK language model loading, models.dev cache/fetch, plugin provider hooks, and provider transforms remain deferred", "ProviderSmoke registry env/config/auth/filter/model fixtures"]],
    ["provider/amazon-bedrock.test.ts", ["partial", "src/opencodehx/smoke/ProviderSmoke.hx; docs/provider-registry-port.md", "Bedrock SDK prefix/getLanguageModel and credential provider chain internals remain deferred", "ProviderSmoke Bedrock config/env/auth fixtures"]],
    ["cli/error.test.ts", ["partial", "src/opencodehx/smoke/CliSmoke.hx; scripts/harness/cli-smoke.mjs", "minimal run/help errors are covered; full yargs/OpenCode CLI errors remain deferred", "CliSmoke plus cli-smoke.mjs"]],
    ["git/git.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "branch/defaultBranch/status/diff/stats and explicit branch-refresh events are covered; native watcher/service bus integration remains deferred", "ProjectRuntimeSmoke Git/VCS fixtures", "opencodehx-hic"]],
    ["installation/installation.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "installation method detection, latest-version lookup for GitHub/npm/bun/pnpm/brew/scoop/choco shapes, release-type classification, upgrade command planning, and package-manager uninstall command planning are covered with typed injected HTTP/process seams; real package-manager side effects remain deferred", "ProjectRuntimeSmoke installationRuntime fixture", "opencodehx-gzn"]],
    ["npm.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "package spec sanitizing, package cache add/install/which/outdated semantics, installation package-manager discovery, uninstall command planning, and config dependency bootstrap are covered through typed injected seams; live package-manager side effects remain deferred", "ProjectRuntimeSmoke npmSanitize/npmRuntime/installationRuntime and ConfigSmoke dependencyBootstrap fixtures", "opencodehx-gzn"]],
    ["project/migrate-global.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "global/no-commit discovery plus storage-backed migration of matching global sessions are covered; fuller database service integration remains deferred", "ProjectRuntimeSmoke projectGlobalMigration fixture", "opencodehx-hic"]],
    ["project/project.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "project discovery, initGit, stable/cached git-root IDs, clone/bare cache behavior, updates/events, initialization timestamps, favicon discovery, sandbox pruning, and stored command updates are covered; fuller config/service integration remains deferred", "ProjectRuntimeSmoke project edge fixtures", "opencodehx-hic"]],
    ["project/vcs.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "git repo discovery, core VCS commands, explicit branch-change events, typed bus propagation, HEAD file-update refresh, and git/branch diff modes are covered; native file watching bindings remain deferred", "ProjectRuntimeSmoke VcsRuntime fixture", "opencodehx-hic"]],
    ["project/worktree-remove.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "worktree remove/delete-branch/sandbox-untrack behavior covers existing and missing worktrees; broader upstream fsmonitor/platform failure matrix remains deferred", "ProjectRuntimeSmoke worktree remove fixture", "opencodehx-hic"]],
    ["project/worktree.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "worktree slug/unique naming, branch, create, ready/failed events, project-ID sharing, sandbox tracking, instance bootstrap/cache/disposal, start commands, and reset/clean are covered; full upstream bootstrap service graph remains deferred", "ProjectRuntimeSmoke worktree edge fixture", "opencodehx-hic"]],
    ["sync/index.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; src/opencodehx/smoke/ServerSmoke.hx; docs/project-runtime-parity.md", "typed sequencing, custom aggregate fields, aggregate history, persistence hooks, publish/replay bus behavior, restart-style reload, remove, server replay/history routes, unknown-type errors, and sequence gaps are covered; full SyncEvent definition/projector/database/GlobalBus/payload registry graph remains deferred", "ProjectRuntimeSmoke SyncEventStore fixture plus ServerSmoke /sync routes", "opencodehx-dlz"]],
    ["control-plane/sse.test.ts", ["partial", "src/opencodehx/smoke/ServerSmoke.hx", "SSE emission is covered by /event; standalone parseSSE helper and multiline parser cases remain deferred", "ServerSmoke /event text fixture"]],
    ["server/session-list.test.ts", ["partial", "src/opencodehx/smoke/ServerSmoke.hx", "basic /session list is covered; directory/root/start/search/limit filters remain deferred", "ServerSmoke GET /session"]],
    ["server/session-messages.test.ts", ["partial", "src/opencodehx/smoke/ServerSmoke.hx", "message page, cursor header, bad cursor, and missing session are covered; high-volume legacy limit remains deferred", "ServerSmoke GET /session/:id/message"]],
    ["server/session-actions.test.ts", ["partial", "src/opencodehx/smoke/ServerSmoke.hx", "abort route success is covered; remaining action routes remain deferred", "ServerSmoke POST /session/:id/abort"]],
    ["server/session-select.test.ts", ["partial", "src/opencodehx/smoke/ServerSmoke.hx", "valid, missing, and invalid select-session cases are covered", "ServerSmoke POST /tui/select-session"]],
  ])
  return exact.get(path)
}

function portRecord(path) {
  const area = areaFor(path)
  const kind = testKind(path)
  const direct = directEvidence(path)
  if (direct) {
    return {
      kind,
      status: direct[0],
      evidence: direct[1],
      reason: direct[2],
      replacement: direct[3],
      next: direct[0] === "ported" ? "none" : (direct[4] ?? nextBeadFor(path, area)),
    }
  }

  if (kind !== "test") {
    return {
      kind,
      status: "reference-only",
      evidence: "upstream fixture/helper retained as oracle input",
      reason: "not an executable upstream test file",
      replacement: "not needed until owning test slice is ported",
      next: nextBeadFor(path, area),
    }
  }

  const areaEvidence = {
    config: "ConfigSmoke covers the first project config parser/loader slice",
    file: "FileSmoke covers initial ignore/path/ripgrep primitives",
    tool: "ToolSmoke covers builtin registry plus core file/bash tools",
    session: "MessageSmoke, StorageSmoke, ProviderSmoke, transcript parity, and SessionProcessorSmoke cover the first message/session slices",
    provider: "FakeProvider and transcript parity cover the credential-free provider fixture",
    storage: "StorageSmoke covers the initial SQLite session store",
    permission: "PermissionSmoke covers the first rule/runtime/tool integration slice",
    util: "UtilSmoke covers selected low-risk utilities",
    cli: "CliSmoke and cli-smoke.mjs cover the headless run scaffold",
  }
  if (areaEvidence[area]) {
    return {
      kind,
      status: "partial",
      evidence: areaEvidence[area],
      reason: "upstream test file has behavior outside the current narrow smoke slice",
      replacement: "current smoke/golden fixture plus pending owning Bead",
      next: nextBeadFor(path, area),
    }
  }

  return {
    kind,
    status: "deferred",
    evidence: "none yet",
    reason: "owning runtime/product slice has not started",
    replacement: "pending fixture in owning Bead",
    next: nextBeadFor(path, area),
  }
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

const portRows = [[
  "test_path",
  "kind",
  "area",
  "priority",
  "port_status",
  "opencodehx_evidence",
  "skip_or_defer_reason",
  "replacement_fixture",
  "next_bead",
]]
const portSummary = new Map()
for (const testPath of testFiles) {
  const area = areaFor(testPath)
  const record = portRecord(testPath)
  portRows.push([
    testPath,
    record.kind,
    area,
    testPriority(testPath),
    record.status,
    record.evidence,
    record.reason,
    record.replacement,
    record.next,
  ])
  const key = `${record.status}:${record.kind}`
  portSummary.set(key, (portSummary.get(key) ?? 0) + 1)
}

writeCsv(join(repoRoot, "reference", "opencode-source-parity-matrix.csv"), sourceRows)
writeCsv(join(repoRoot, "reference", "opencode-test-priority-matrix.csv"), testRows)
writeCsv(join(repoRoot, "reference", "opencode-test-port-matrix.csv"), portRows)

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
  `- Test port matrix: \`reference/opencode-test-port-matrix.csv\``,
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

const statusSummary = [...portSummary.entries()]
  .sort((a, b) => a[0].localeCompare(b[0]))
  .map(([key, count]) => {
    const [status, kind] = key.split(":")
    return `| ${status} | ${kind} | ${count} |`
  })

const portMarkdown = [
  "# OpenCode Test Port Matrix",
  "",
  "**Bead:** `opencodehx-039`",
  "",
  "## Summary",
  "",
  `- Upstream test root: \`${relative(repoRoot, testRoot)}\``,
  `- Upstream test items tracked: ${totalTests}`,
  `- Machine-readable matrix: \`reference/opencode-test-port-matrix.csv\``,
  "",
  "| Port status | Kind | Count |",
  "| --- | --- | ---: |",
  ...statusSummary,
  "",
  "## Status Meanings",
  "",
  "- `ported`: current OpenCodeHX smoke/golden evidence covers the upstream item's core behavior.",
  "- `partial`: current evidence covers part of the upstream behavior, but the matrix names the missing scope and owning Bead.",
  "- `deferred`: no replacement exists yet because the owning product/runtime slice has not started.",
  "- `reference-only`: upstream fixture/helper/document input, not an executable test. It remains an oracle input for the owning slice.",
  "",
  "Every `partial` or `deferred` executable test row has a `skip_or_defer_reason`, a current or pending `replacement_fixture`, and a `next_bead` owner. Keep this file generated from `scripts/inventory/build-parity-matrix.mjs` so status changes are reviewable instead of drifting into markdown prose.",
  "",
  "## Current Reading",
  "",
  "OpenCodeHX has direct executable evidence for selected utility, config, file, message, storage, tool, permission, provider, CLI, project/git/worktree/sync/npm, and one-turn session behavior. Large product surfaces remain deferred: server/API, SDK compatibility, real providers, full session lifecycle, MCP/ACP, plugin loading, LSP, live TUI, live package-manager installation side effects, and packaging.",
  "",
  "The next practical move is to use this matrix while selecting Beads: before starting a subsystem, filter `reference/opencode-test-port-matrix.csv` by `next_bead` and promote the relevant upstream tests into Haxe-owned fixtures or differential harnesses.",
  "",
].join("\n")

writeFileSync(join(repoRoot, "docs", "opencode-test-port-matrix.md"), portMarkdown)
