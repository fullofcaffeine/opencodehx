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

const m11Owners = {
  foundation: "opencodehx-000.11",
  session: "opencodehx-000.2",
  provider: "opencodehx-000.3",
  server: "opencodehx-000.4",
  plugin: "opencodehx-000.5",
  protocol: "opencodehx-000.6",
  lsp: "opencodehx-000.7",
  tui: "opencodehx-000.8",
  tool: "opencodehx-000.9",
}

function nextBeadFor(path, area) {
  if (path.includes("/tui/") || area === "tui") return m11Owners.tui
  if (area === "server" || area === "control-plane") return m11Owners.server
  if (area === "session" || area === "agent" || area === "question") return m11Owners.session
  if (area === "provider" || area === "account" || area === "auth") return m11Owners.provider
  if (area === "tool" || area === "patch" || area === "snapshot" || area === "share") return m11Owners.tool
  if (area === "mcp" || area === "acp") return m11Owners.protocol
  if (area === "lsp" || area === "ide") return m11Owners.lsp
  if (area === "plugin" || area === "skill") return m11Owners.plugin
  return m11Owners.foundation
}

function directEvidence(path) {
  const exact = new Map([
    ["account/repo.test.ts", ["direct", "src/opencodehx/account/AccountRepo.hx; src/opencodehx/smoke/AccountSmoke.hx; docs/account-repo.md", "Effect service layering is not ported here, but upstream SQLite account row/state semantics are covered against an isolated temp database", "AccountSmoke account repo fixtures", "none"]],
    ["account/service.test.ts", ["direct", "src/opencodehx/account/AccountService.hx; src/opencodehx/account/AccountRepo.hx; src/opencodehx/smoke/AccountSmoke.hx; docs/account-repo.md", "full upstream account service test behavior is covered through an injected HTTP client; full Effect service layering and live CLI account side effects remain outside this row", "AccountSmoke async account service fixtures", "none"]],
    ["util/format.test.ts", ["ported", "src/opencodehx/smoke/UtilSmoke.hx#formatDuration; docs/util-port.md", "none", "UtilSmoke.formatDuration"]],
    ["util/lazy.test.ts", ["ported", "src/opencodehx/smoke/UtilSmoke.hx#lazy; docs/util-port.md", "none", "UtilSmoke.lazy"]],
    ["util/iife.test.ts", ["ported", "src/opencodehx/util/Iife.hx; src/opencodehx/smoke/UtilSmoke.hx#iife; docs/util-port.md", "none", "UtilSmoke.iife"]],
    ["util/data-url.test.ts", ["ported", "src/opencodehx/smoke/UtilSmoke.hx#dataUrl; docs/util-port.md", "none", "UtilSmoke.dataUrl"]],
    ["util/glob.test.ts", ["ported", "src/opencodehx/util/GlobRuntime.hx; src/opencodehx/smoke/UtilSmoke.hx#glob; docs/util-port.md", "none", "UtilSmoke.glob"]],
    ["util/wildcard.test.ts", ["ported", "src/opencodehx/util/Wildcard.hx; src/opencodehx/smoke/UtilSmoke.hx#wildcard; docs/util-port.md", "none", "UtilSmoke.wildcard"]],
    ["util/which.test.ts", ["ported", "src/opencodehx/util/Which.hx; src/opencodehx/smoke/UtilSmoke.hx#which; docs/util-port.md", "none", "UtilSmoke.which"]],
    ["util/module.test.ts", ["ported", "src/opencodehx/util/ModuleResolver.hx; src/opencodehx/smoke/UtilSmoke.hx#moduleResolver; docs/util-port.md", "none", "UtilSmoke.moduleResolver"]],
    ["util/log.test.ts", ["ported", "src/opencodehx/util/LogRuntime.hx; src/opencodehx/smoke/UtilSmoke.hx#logCleanup; docs/util-port.md", "none", "UtilSmoke.logCleanup"]],
    ["util/timeout.test.ts", ["ported", "src/opencodehx/util/Timeout.hx; src/opencodehx/smoke/UtilSmoke.hx#timeout; docs/util-port.md", "none", "UtilSmoke.timeout"]],
    ["util/lock.test.ts", ["ported", "src/opencodehx/util/Lock.hx; src/opencodehx/smoke/UtilSmoke.hx#lock; docs/util-port.md", "none", "UtilSmoke.lock"]],
    ["util/process.test.ts", ["ported", "src/opencodehx/util/ProcessRuntime.hx; src/opencodehx/smoke/UtilSmoke.hx#process; docs/util-port.md", "none", "UtilSmoke.process"]],
    ["util/filesystem.test.ts", ["ported", "src/opencodehx/file/AppFileSystem.hx; src/opencodehx/smoke/FileSmoke.hx; docs/file-port.md", "none", "FileSmoke.appFileSystem/FileSmoke.runAsync"]],
    ["util/error.test.ts", ["ported", "src/opencodehx/smoke/UtilSmoke.hx#errorTools; docs/error-diagnostics-parity.md", "none", "UtilSmoke.errorTools golden"]],
    [
      "memory/abort-leak.test.ts",
      [
        "partial",
        "src/opencodehx/util/Abort.hx; src/opencodehx/smoke/UtilSmoke.hx#abort; scripts/harness/abort-leak-smoke.mjs; docs/util-port.md",
        "Bun GC heap-growth worker oracle is covered by an opt-in host-sensitive harness and is not a default Node smoke",
        "UtilSmoke.abort plus npm run memory:abort:smoke",
      ],
    ],
    ["format/format.test.ts", ["ported", "src/opencodehx/format/FormatRuntime.hx; src/opencodehx/smoke/FormatterSmoke.hx; docs/formatter-port.md", "none", "FormatterSmoke"]],
    ["auth/auth.test.ts", ["direct", "src/opencodehx/auth/AuthStore.hx; src/opencodehx/smoke/AuthSmoke.hx; docs/provider-registry-port.md", "real Effect service layering remains deferred, but upstream set/remove key normalization behavior is covered against temp XDG auth.json storage", "AuthSmoke auth store normalization fixtures", "none"]],
    ["bus/bus-effect.test.ts", ["partial", "src/opencodehx/bus/BusStreamRuntime.hx; src/opencodehx/bus/GlobalBusRuntime.hx; src/opencodehx/smoke/BusSmoke.hx; docs/bus-runtime-parity.md", "observable stream delivery, subscribeAll filtering, multi-subscriber behavior, upstream-shaped GlobalBus event emission, and server.instance.disposed directory payload are covered; full upstream Effect Layer/Deferred/scoped fiber and Instance.provide service wiring remain deferred", "BusSmoke streamDelivery/globalBusEmit/instanceDisposal"]],
    ["effect/app-runtime-logger.test.ts", ["partial", "src/opencodehx/effect/AppRuntimeLoggerRuntime.hx; src/opencodehx/smoke/EffectSmoke.hx; docs/effect-runtime-parity.md", "full Effect ManagedRuntime/Layer/Context.Service, runFork/runCallback, real Logger.CurrentLoggers, and ALS-backed InstanceRef integration remain deferred", "EffectSmoke.appRuntimeLogger/appRuntimeLoggerBridge"]],
    ["effect/cross-spawn-spawner.test.ts", ["partial", "src/opencodehx/util/ProcessRuntime.hx; src/opencodehx/smoke/EffectSmoke.hx; docs/effect-runtime-parity.md", "full Effect ChildProcessSpawner service, Stream byte chunks, scoped child cleanup, multi-stage pipeTo pipeline helpers, and native Windows-only execution remain deferred", "EffectSmoke.crossSpawnSpawner"]],
    ["effect/instance-state.test.ts", ["partial", "src/opencodehx/effect/InstanceStateRuntime.hx; src/opencodehx/smoke/EffectSmoke.hx; docs/effect-runtime-parity.md", "ALS-backed InstanceRef and async-boundary/high-contention context propagation remain deferred", "EffectSmoke.instanceState"]],
    ["effect/observability.test.ts", ["partial", "src/opencodehx/effect/ObservabilityResource.hx; src/opencodehx/smoke/EffectSmoke.hx; docs/effect-runtime-parity.md", "OTLP logger/layer and trace exporter wiring remain deferred", "EffectSmoke.observabilityResource"]],
    ["effect/runner.test.ts", ["partial", "src/opencodehx/effect/RunnerRuntime.hx; src/opencodehx/smoke/EffectSmoke.hx; docs/effect-runtime-parity.md", "shared success/failure delivery, ignored replacement work, cancellation fallback, queued caller settlement, restart-after-cancel, and pending-interrupt replacement interleaving are covered; real Effect Scope/Fiber interruption, shell states, lifecycle callbacks, and scoped cleanup remain deferred", "EffectSmoke.runner"]],
    ["effect/run-service.test.ts", ["partial", "src/opencodehx/effect/RuntimeMemo.hx; src/opencodehx/effect/RunServiceRuntime.hx; src/opencodehx/smoke/EffectSmoke.hx; docs/effect-runtime-parity.md", "memoized shared dependency, Promise-backed service execution, typed exits, callback delivery, and deterministic fork completion/interruption are covered; full Effect ManagedRuntime/Layer/Context.Service and real Fiber semantics remain deferred", "EffectSmoke.runServiceMemoMap/runServiceAsync"]],
    ["fake/provider.ts", ["ported", "src/opencodehx/provider/FakeProvider.hx; scripts/harness/transcript-parity.mjs; docs/fake-provider-transcript-harness.md", "none", "FakeProvider plus one-turn golden transcript"]],
    ["fixture/fixture.test.ts", ["ported", "src/opencodehx/smoke/SmokeTmpDir.hx; src/opencodehx/smoke/FixtureSmoke.hx; docs/fixture-smoke-parity.md", "none", "FixtureSmoke.tmpdir"]],
    ["session/message-v2.test.ts", ["partial", "src/opencodehx/smoke/MessageSmoke.hx; src/opencodehx/smoke/SessionProcessorSmoke.hx; docs/message-v2-port.md; docs/session-processor-one-turn.md", "broader prompt/session lifecycle cases remain partial; live AI SDK recovered history now covers text, provider metadata, compaction/subtask prompts, user file parts, assistant tool-call/tool-result parts, media-capable tool-result attachments, unsupported-provider synthetic media injection, interrupted tool output, normal tool errors, and Anthropic provider-transform handling for recovered media tool results", "MessageSmoke codec/part/cursor fixtures plus SessionProcessorSmoke rich recovered-history and provider-transform history prompts"]],
    [
      "session/instruction.test.ts",
      [
        "partial",
        "src/opencodehx/session/SessionInstruction.hx; src/opencodehx/session/SessionInstructionClaims.hx; src/opencodehx/smoke/SessionProcessorSmoke.hx; src/opencodehx/smoke/ToolSmoke.hx; scripts/harness/cli-smoke.mjs; scripts/harness/package-smoke.mjs; docs/session-processor-one-turn.md",
        "full upstream Effect service/prompt lifecycle integration remains deferred",
        "SessionInstruction systemPaths/system smoke covers project/root AGENTS.md lookup, config.instructions local file entries, remote instruction URL fetch/failed-fetch omission for async live prompts, non-git containment, live CLI/package request-body instruction evidence, read-tool nearby instruction discovery, per-message claim dedupe/clear for repeated reads, and completed read-tool metadata loaded-history extraction from recovered messages",
      ],
    ],
    ["session/processor-effect.test.ts", ["partial", "src/opencodehx/smoke/SessionProcessorSmoke.hx; docs/session-processor-one-turn.md", "current processor is one-turn and synchronous; upstream Effect streaming lifecycle remains deferred", "SessionProcessorSmoke"]],
    [
      "session/llm.test.ts",
      [
        "partial",
        "fixtures/transcripts/one-turn.golden.json; scripts/harness/transcript-parity.mjs; scripts/harness/cli-smoke.mjs; src/opencodehx/session/SessionLlm.hx; src/opencodehx/smoke/SessionProcessorSmoke.hx",
        "external credential-backed success evidence plus real retry backoff timing/broader cancellation lifecycle remain deferred",
        "one-turn fake-provider transcript golden plus credential-free async AI SDK session/CLI harness including pure hasToolCalls helper coverage, prompt-permission active-tool filtering, tool-call repair/fallback, request-option merge order, chat parameter assembly, streamText option assembly, stream-prompt transform branching, telemetry option assembly, stream failure error mapping, workflow model state/preapproval shaping, workflow approval shaping, workflow tool-executor result/error shaping, active-tool-name and workflow preapproval filtering, LiteLLM/GitHub Copilot _noop compatibility tool injection, streaming request header assembly and override order, system prompt assembly/transform/request-message branching, public ModelMessage prompt input evidence for initial streamText calls, recovered text/file/tool/provider-metadata/media-capable-tool-result/unsupported-media-injection/provider-transform/compaction/subtask/interrupted-output-history prompt construction, accumulated public assistant tool-call/tool-result continuation history, text/tool export ordering and tool input/output/error sanitization, AI SDK text/tool store-backed recovery plus stream error and abort propagation with assistant finish metadata alignment, persisted/exported MessageAbortedError state for initial and tool-result continuation cancellation, retryable live stream-error retry status/part recording, deterministic live AI SDK retry loop scheduling after retryable initial and continuation stream errors, first server session status/abort route evidence, injected and config-backed server-owned live AI SDK route evidence with active busy status, default-agent/provider selection, and abort-signal propagation during async streaming, first model-emitted tool-call dispatch, live tool schema advertisement, live provider message-transform middleware evidence, repeated continuation after successful tool results with explicit opt-out/max-continuation cap evidence, live mock-model inspection proving max output tokens, temperature, topP, topK, request headers, transformed provider options, variant-selected options, selected-agent request assembly, disabled-tool filtering/rejection, and continuation request options reach streamText calls, non-interactive fork child-session persistence, live-registry CLI validation with well-known remote config plus global/project config/auth storage/active-account config discovery, local no-network OpenAI-compatible streaming success/provider-error persistence, local live default-agent request-body evidence, local live read/write/edit/apply_patch/bash tool-call continuation/export persistence with write/edit/patch/bash side-effect verification, live write-then-read multi-step tool-chain continuation, config-denied and permission-skipped live write tool enforcement including skip-flag deny precedence, and live run default/OPENCODE_DB export/resume/continue/fork persistence",
        m11Owners.session,
      ],
    ],
    [
      "storage/storage.test.ts",
      [
        "partial",
        "src/opencodehx/storage/StorageJsonRuntime.hx; src/opencodehx/smoke/StorageSmoke.hx; docs/storage-port.md",
        "generic JSON write/read/update/remove/list behavior, per-key concurrent JSON update serialization, and session/message CRUD are covered; real Effect service layering and full Drizzle/AppFileSystem integration remain deferred",
        "StorageSmoke.jsonKeyValueStorage/jsonConcurrentUpdates plus session/message CRUD",
      ],
    ],
    ["storage/json-migration.test.ts", ["partial", "src/opencodehx/storage/JsonStorageMigrationRuntime.hx; src/opencodehx/smoke/StorageSmoke.hx; docs/storage-port.md", "project/session/message/part migration, parent orphan skipping, unreadable-file error collection, and typed todo/permission/session-share side-table summaries are covered; persisted side tables, full Drizzle migration compatibility, and storage service integration remain deferred", "StorageSmoke.jsonMigration"]],
    ["storage/db.test.ts", ["ported", "src/opencodehx/storage/StorageDatabasePath.hx; src/opencodehx/smoke/StorageSmoke.hx; docs/storage-port.md", "none", "StorageSmoke databasePath"]],
    ["config/config.test.ts", ["partial", "src/opencodehx/smoke/ConfigSmoke.hx; src/opencodehx/smoke/ServerSmoke.hx; src/opencodehx/config/ConfigLoader.hx; src/opencodehx/account/AccountService.hx; docs/config-port.md", "runtime plugin loading/path resolution and live package-manager dependency install side effects remain deferred; deterministic dependency bootstrap gitignore/install success/failure and active-account service config/token substitution are covered", "ConfigSmoke plus ServerSmoke GET /config and GET /config/providers route fixtures"]],
    [
      "config/tui.test.ts",
      [
        "partial",
        "src/opencodehx/config/ConfigTui.hx; src/opencodehx/smoke/ConfigSmoke.hx; docs/config-port.md",
        "focused TUI config loader covers tui.json/global/env/project/.opencode precedence, nested tui flattening, keybind/plugin/plugin_enabled merges, tuple plugin options, Windows terminal suspend/input undo normalization, legacy opencode.json migration with backup/strip/read-only fallback, and env/file substitution; dependency install side effects and full TUI service/runtime layering remain deferred",
        "ConfigSmoke.tuiConfig",
        m11Owners.foundation,
      ],
    ],
    ["config/agent-color.test.ts", ["direct", "src/opencodehx/smoke/ConfigSmoke.hx; src/opencodehx/smoke/UtilSmoke.hx; src/opencodehx/agent/AgentRuntime.hx; src/opencodehx/util/Color.hx; docs/config-port.md", "project JSON agent colors, config-backed agent lookup color propagation, and strict hex-to-ANSI conversion are covered", "ConfigSmoke agentColorConfig plus UtilSmoke color", "none"]],
    ["config/lsp.test.ts", ["direct", "src/opencodehx/config/ConfigLsp.hx; src/opencodehx/smoke/ConfigSmoke.hx; docs/config-port.md", "LSP config refinement is covered for boolean toggles, builtin TypeScript config, custom servers with extensions, disabled custom servers, mixed configs, missing-extension failures, and empty-extension current behavior", "ConfigSmoke lspConfigRefinement", "none"]],
    ["config/markdown.test.ts", ["direct", "src/opencodehx/config/ConfigMarkdown.hx; src/opencodehx/smoke/ConfigSmoke.hx; docs/config-port.md", "file-reference extraction and frontmatter parsing fixture behavior are covered, including comments, colon-heavy values, block scalars, empty/no frontmatter, Markdown headers, weird model IDs, nested tool maps, and content preservation", "ConfigSmoke markdownParsing", "none"]],
    ["cli/github-action.test.ts", ["direct", "src/opencodehx/cli/GitHubAction.hx; src/opencodehx/smoke/CliSmoke.hx; docs/cli-command-surface.md", "pure GitHub action helpers cover response text extraction from typed message parts and prompt-too-large diagnostics for attached files; live GitHub action execution remains deferred", "CliSmoke.githubActionHelpers", "none"]],
    ["cli/github-remote.test.ts", ["direct", "src/opencodehx/cli/GitHubRemote.hx; src/opencodehx/smoke/CliSmoke.hx; docs/cli-command-surface.md", "pure GitHub remote URL parsing covers HTTPS/HTTP, git@, ssh://git@, .git suffixes, hyphen/underscore/number/dot names, non-GitHub remotes, invalid URLs, missing owner/repo, and extra path rejection; GitHub action execution remains deferred", "CliSmoke.githubRemoteParser", "none"]],
    ["cli/plugin-auth-picker.test.ts", ["direct", "src/opencodehx/cli/PluginAuthPicker.hx; src/opencodehx/smoke/PluginSmoke.hx; docs/cli-command-surface.md; docs/plugin-runtime-minimum.md", "typed plugin-auth provider picker helper covers plugin-only providers, models.dev exclusion, dedupe, disabled/enabled filters, configured provider display names, fallback IDs, hooks without auth, and empty hooks", "PluginSmoke.pluginAuthPicker", "none"]],
    ["config/plugin.test.ts", ["reference-only", "upstream config/plugin.test.ts is empty; plugin config behavior is covered by ConfigSmoke and docs/config-port.md", "no executable upstream assertions are present in this file", "ConfigSmoke pluginMergeAndOrigins/pluginDirectoryDiscovery/pluginPathResolution/dependencyBootstrap", "none"]],
    ["plugin/auth-override.test.ts", ["partial", "src/opencodehx/plugin/PluginAuthHooks.hx; src/opencodehx/plugin/PluginConfigHooks.hx; src/opencodehx/provider/ProviderAuthRuntime.hx; src/opencodehx/smoke/PluginSmoke.hx; src/opencodehx/smoke/ProviderSmoke.hx; src/opencodehx/smoke/ServerSmoke.hx; docs/plugin-runtime-minimum.md; docs/provider-registry-port.md", "typed auth-method override precedence, prompt metadata modeling, config-hook error isolation, server provider-auth method output, and no-network OAuth authorize/callback persistence are covered; live plugin file loading, built-in auth browser/device flows, and install side effects remain deferred", "PluginSmoke.authOverride plus ProviderSmoke registryPluginConfigHooks isolation plus ServerSmoke GET /provider/auth and POST provider OAuth fixtures", m11Owners.plugin]],
    ["plugin/shared.test.ts", ["ported", "src/opencodehx/plugin/PluginShared.hx; src/opencodehx/smoke/PluginSmoke.hx; docs/plugin-runtime-minimum.md", "none", "PluginSmoke.parseSpecifiers"]],
    ["plugin/meta.test.ts", ["partial", "src/opencodehx/plugin/PluginMeta.hx; src/opencodehx/smoke/PluginSmoke.hx; docs/plugin-runtime-minimum.md", "file and npm metadata state transitions plus cross-process metadata serialization are covered; live plugin install/loading integration remains deferred", "PluginSmoke.metadata/metadataConcurrent", m11Owners.plugin]],
    ["plugin/loader-shared.test.ts", ["partial", "src/opencodehx/plugin/PluginRuntime.hx; src/opencodehx/plugin/PluginShared.hx; src/opencodehx/smoke/PluginSmoke.hx; docs/plugin-runtime-minimum.md", "injected module-provider loader shape covers default V1 precedence, V1 rejection, legacy dedupe, missing modules, package metadata, and plugin ID rules; live dynamic import/file side effects/package install paths remain deferred", "PluginSmoke.runtime", m11Owners.plugin]],
    ["plugin/trigger.test.ts", ["partial", "src/opencodehx/plugin/PluginRuntime.hx; src/opencodehx/smoke/PluginSmoke.hx; docs/plugin-runtime-minimum.md", "synchronous system-transform hook ordering and async hook awaiting are covered; full Plugin service integration and live plugin file loading remain deferred", "PluginSmoke.runtime/runtimeAsync trigger hook order", m11Owners.plugin]],
    ["plugin/codex.test.ts", ["partial", "src/opencodehx/plugin/PluginCodex.hx; src/opencodehx/smoke/PluginSmoke.hx; docs/plugin-runtime-minimum.md", "JWT claim parsing and ChatGPT account-id extraction are covered; live Codex OAuth/device/browser auth plugin behavior remains deferred", "PluginSmoke.codexJwtClaims", m11Owners.plugin]],
    ["plugin/cloudflare.test.ts", ["partial", "src/opencodehx/plugin/PluginCloudflare.hx; src/opencodehx/smoke/PluginSmoke.hx; docs/plugin-runtime-minimum.md", "Cloudflare AI Gateway chat-params maxOutputTokens rule is covered; full built-in auth plugin/provider auth override flow remains deferred", "PluginSmoke.cloudflareChatParams", m11Owners.plugin]],
    ["plugin/github-copilot-models.test.ts", ["partial", "src/opencodehx/plugin/PluginGithubCopilotModels.hx; src/opencodehx/smoke/PluginSmoke.hx; docs/plugin-runtime-minimum.md", "GitHub Copilot model merge/remap rules are covered; live Copilot OAuth/device/browser auth, credential-backed model fetch, and chat header/param hooks remain deferred", "PluginSmoke.githubCopilotModels", m11Owners.plugin]],
    ["plugin/workspace-adaptor.test.ts", ["partial", "src/opencodehx/plugin/PluginWorkspaceRuntime.hx; src/opencodehx/controlplane/WorkspaceAdaptors.hx; src/opencodehx/smoke/ControlPlaneSmoke.hx; docs/plugin-runtime-minimum.md; docs/server-hono-seam.md", "typed plugin-facing workspace adaptor registration/configure/create/target behavior is covered; live plugin file loading, experimental flag wiring, and full Workspace.create persistence remain deferred", "ControlPlaneSmoke.pluginWorkspaceRegistration", m11Owners.plugin]],
    ["workspace/workspace-restore.test.ts", ["partial", "src/opencodehx/controlplane/WorkspaceRestoreRuntime.hx; src/opencodehx/smoke/ControlPlaneSmoke.hx; docs/project-runtime-parity.md", "full database/AppRuntime/Workspace service integration and persisted session workspace updates remain deferred", "ControlPlaneSmoke.workspaceRestoreRemote/workspaceRestoreLocal", "opencodehx-000.11"]],
    ["question/question.test.ts", ["partial", "src/opencodehx/question/QuestionRuntime.hx; src/opencodehx/smoke/QuestionSmoke.hx; src/opencodehx/smoke/ServerSmoke.hx; docs/question-runtime.md", "typed ask/list/reply/reject behavior, directory isolation, dispose/reload rejection, and server list/reply/reject routes are covered; Effect Layer/Deferred integration, question tool wrapper, and UI prompts remain deferred", "QuestionSmoke plus ServerSmoke /question route fixtures", m11Owners.session]],
    ["skill/skill.test.ts", ["partial", "src/opencodehx/smoke/SkillSmoke.hx; docs/skill-registry-port.md", "Effect service integration and binary remote skill resources remain deferred", "SkillRegistry local/remote discovery and availability smoke"]],
    ["skill/discovery.test.ts", ["partial", "src/opencodehx/smoke/SkillSmoke.hx; docs/skill-registry-port.md", "Effect service integration and binary remote skill resources remain deferred", "SkillRemoteDiscovery cache/download smoke"]],
    [
      "session/system.test.ts",
      [
        "partial",
        "src/opencodehx/session/SessionSystemPrompt.hx; src/opencodehx/session/SessionInstruction.hx; src/opencodehx/session/SessionInstructionClaims.hx; src/opencodehx/smoke/SessionProcessorSmoke.hx; src/opencodehx/smoke/SkillSmoke.hx; src/opencodehx/smoke/ToolSmoke.hx; scripts/harness/cli-smoke.mjs; scripts/harness/package-smoke.mjs; docs/session-processor-one-turn.md",
        "full Plugin service integration and reminder prompt insertion remain deferred",
        "SessionSystemPrompt provider/environment/skills/instruction assembly including async remote instruction URL bodies plus SkillRegistry sorted verbose and permission-filtered availability smoke; SessionProcessorSmoke proves typed plugin system transforms preserve upstream two-part finalization; generated CLI and package smokes prove assembled system prompt reaches request body; ToolSmoke proves read-tool per-message instruction claim dedupe/clear; SessionProcessorSmoke proves recovered read-tool loaded metadata suppresses repeated nearby reminders",
      ],
    ],
    ["bus/bus.test.ts", ["ported", "src/opencodehx/bus/BusRuntime.hx; src/opencodehx/smoke/BusSmoke.hx; docs/bus-runtime-parity.md", "none", "BusSmoke callback and scoped lifecycle fixtures"]],
    ["bus/bus-integration.test.ts", ["ported", "src/opencodehx/bus/BusRuntime.hx; src/opencodehx/smoke/BusSmoke.hx; docs/bus-runtime-parity.md", "none", "BusSmoke callback and scoped lifecycle fixtures"]],
    [
      "file/fsmonitor.test.ts",
      [
        "partial",
        "src/opencodehx/git/Git.hx; src/opencodehx/file/FileSystem.hx; src/opencodehx/smoke/FileSmoke.hx; docs/file-port.md",
        "status/read command paths disable Git fsmonitor and are smoke-tested with repo core.fsmonitor=true; native Windows daemon lifecycle remains host-conditional",
        "FileSmoke.fsmonitorGuard",
        m11Owners.foundation,
      ],
    ],
    [
      "file/ignore.test.ts",
      [
        "direct",
        "src/opencodehx/file/FileIgnore.hx; src/opencodehx/smoke/FileSmoke.hx; docs/file-port.md",
        "node_modules nested and non-nested match cases are covered",
        "FileSmoke.ignoreRules",
        "none",
      ],
    ],
    [
      "file/index.test.ts",
      [
        "partial",
        "src/opencodehx/file/FileSystem.hx; src/opencodehx/file/FileSearchRuntime.hx; src/opencodehx/project/VcsRuntime.hx; src/opencodehx/smoke/FileSmoke.hx; src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/file-port.md; docs/project-runtime-parity.md",
        "Full File.Service cache/state machine, exact fuzzysort ranking, exact diff package patch formatting, and Effect integration remain deferred",
        "FileSmoke.readFiles/readDiffs/listEdges/fileSearch plus ProjectRuntimeSmoke.fileStatusParity cover read/list/search and status cases including modified/added/deleted/mixed/clean/non-git/binary behavior",
        m11Owners.foundation,
      ],
    ],
    [
      "file/ripgrep.test.ts",
      [
        "partial",
        "src/opencodehx/file/Ripgrep.hx; src/opencodehx/smoke/FileSmoke.hx; docs/file-port.md",
        "ripgrep command behavior is covered; Effect stream service shape and separate worker-mode implementation parity remain deferred",
        "FileSmoke.ripgrepFiles/ripgrepSearch",
        m11Owners.foundation,
      ],
    ],
    [
      "file/path-traversal.test.ts",
      [
        "direct",
        "src/opencodehx/file/FileSystem.hx; src/opencodehx/project/InstanceRuntime.hx; src/opencodehx/smoke/FileSmoke.hx; src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/file-port.md; docs/project-runtime-parity.md",
        "File read/list path traversal, Filesystem.contains, and InstanceRuntime.containsPath worktree/monorepo/non-git containment cases are covered",
        "FileSmoke.pathSafety plus ProjectRuntimeSmoke.instanceContainsPath",
        "none",
      ],
    ],
    [
      "filesystem/filesystem.test.ts",
      [
        "direct",
        "src/opencodehx/file/AppFileSystem.hx; src/opencodehx/smoke/FileSmoke.hx; docs/file-port.md",
        "AppFileSystem helper behavior is covered for directory/file predicates, JSON, recursive writes, ancestor search, glob helpers, passthrough exists/remove, MIME, contains, and overlaps",
        "FileSmoke.appFileSystem",
        "none",
      ],
    ],
    [
      "file/watcher.test.ts",
      [
        "partial",
        "src/opencodehx/file/FileWatcherRuntime.hx; src/opencodehx/smoke/ProjectRuntimeSmoke.hx; scripts/harness/file-watcher-smoke.mjs; docs/file-port.md; docs/project-runtime-parity.md",
        "deterministic service behavior is covered; native @parcel/watcher backend parity and timing-sensitive CI behavior remain deferred",
        "ProjectRuntimeSmoke.fileWatcherService/vcsWatcherEvents plus opt-in file-watcher-smoke.mjs",
        m11Owners.foundation,
      ],
    ],
    ["tool/glob.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/tool-registry-port.md", "core glob cases plus typed permission request/denial and external-directory search-root shape are covered; full Effect context parity remains deferred", "ToolSmoke.globExec"]],
    ["tool/grep.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/tool-registry-port.md", "core grep cases, exact-file search, no-match output, typed permission request/denial, and external-directory file-target shape are covered; full Effect context remains deferred", "ToolSmoke.grepExec"]],
    ["tool/read.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/core-file-tools-port.md", "representative read file/directory/error behavior, file offset errors, empty-file offsets, .fbs schema text output, byte-cap and line-count truncation footers, upstream-shaped missing-file suggestions, long-line truncation suffixes, known binary extension rejection, directory pagination, symlinked-directory suffixes, image/PDF media attachments with content sniffing, absolute read permission patterns, external-directory read prompts, nearby instruction reminder metadata, and per-message instruction claim dedupe/clear are covered; fuller upstream output matrix remains deferred", "ToolSmoke.readExec plus PermissionSmoke.toolIntegration"]],
    ["tool/write.test.ts", ["partial", "src/opencodehx/tool/WriteTool.hx; src/opencodehx/smoke/ToolSmoke.hx; docs/core-file-tools-port.md", "write creation, overwrite metadata, JSON/binary-safe/empty/multiline/CRLF content preservation, relative title output, diff/filediff metadata, BOM preservation including formatter-strip restore, file.edited plus file.watcher add/change publication, and external-directory write permission shape are covered; LSP diagnostics and full async Format service integration remain deferred", "ToolSmoke.writeExec"]],
    [
      "tool/edit.test.ts",
      [
        "partial",
        "src/opencodehx/tool/EditTool.hx; src/opencodehx/smoke/ToolSmoke.hx; docs/core-file-tools-port.md",
        "representative exact/multiline/replace-all/multiple-match behavior, identical-input and directory-path failures, filediff stats, tolerant fallback behavior, CRLF/BOM preservation including formatter-strip restore, file.edited plus file.watcher add/change publication, and external-directory edit permission shape are covered; full upstream async Format service and LSP matrix remain deferred",
        "ToolSmoke.editExec",
      ],
    ],
    [
      "tool/apply_patch.test.ts",
      [
        "partial",
        "src/opencodehx/tool/ApplyPatchTool.hx; src/opencodehx/smoke/ToolSmoke.hx; docs/core-file-tools-port.md",
        "representative add/update/delete/move, insert-only hunks, BOM preservation including formatter-strip restore, file.edited plus file.watcher add/change/unlink publication, EOF, context disambiguation, heredoc with/without cat, whitespace/Unicode matching, malformed/delete-target failures, no-side-effect behavior, and external-directory hunk/move-target permission shape are covered; full upstream async Format service, Effect/LSP matrix remains deferred",
        "ToolSmoke.applyPatchExec",
      ],
    ],
    ["patch/patch.test.ts", ["direct", "src/opencodehx/patch/PatchRuntime.hx; src/opencodehx/smoke/PatchSmoke.hx; docs/patch-runtime.md", "standalone Patch namespace behavior is covered for parsePatch, maybeParseApplyPatch, applyPatch add/update/delete/move/nested/error/edge cases, and verified planning", "PatchSmoke", "none"]],
    ["tool/bash.test.ts", ["partial", "src/opencodehx/tool/BashTool.hx; src/opencodehx/tool/Truncate.hx; src/opencodehx/smoke/ToolSmoke.hx; docs/bash-shell-seam.md", "non-interactive Node shell seam, tree-sitter Bash scanner prompts, workdir and wildcard path external-directory permissions, timeout metadata, and truncation spill files with metadata.outputPath are covered; streaming metadata updates and full PowerShell/Windows matrix remain deferred", "ToolSmoke.bashExec and BashCommandScanner fixtures", m11Owners.tool]],
    ["tool/tool-define.test.ts", ["partial", "src/opencodehx/tool/ToolDefinition.hx; src/opencodehx/smoke/ToolSmoke.hx; docs/tool-registry-port.md", "fresh init snapshots for object-defined and factory-defined Haxe tool definitions are covered; upstream Effect/Zod Tool.define wrapping remains deferred", "ToolSmoke.toolDefinitionFresh", m11Owners.tool]],
    ["tool/truncation.test.ts", ["partial", "src/opencodehx/tool/Truncate.hx; src/opencodehx/tool/BashTool.hx; src/opencodehx/smoke/ToolSmoke.hx; docs/core-file-tools-port.md; docs/bash-shell-seam.md", "standalone Truncate output/write/cleanup covers default limits, head/tail direction, byte/line truncation, full-output spill files, retention cleanup, and Task-vs-Grep hints; BashTool now writes full truncated output to spill files and reports metadata.outputPath; read, glob, and grep still expose representative inline truncation metadata/output, while full Effect layer wiring and every caller using the shared Truncate service remain deferred", "ToolSmoke.truncateRuntime plus BashTool byte/line spill fixtures and read/glob/grep truncation fixtures", m11Owners.tool]],
    [
      "snapshot/snapshot.test.ts",
      [
        "partial",
        "src/opencodehx/snapshot/SnapshotRuntime.hx; src/opencodehx/smoke/SnapshotSmoke.hx; docs/snapshot-runtime.md",
        "focused snapshot runtime covers deterministic track hashes, patch detection for added/modified/deleted files, revert restore/delete behavior, empty-directory no-op, invalid-hash empty patch, large added-file skip/stable hash, gitignore filtering, and simple diff/diffFull evidence; persistent separate Git-dir lifecycle, full restore semantics, rich diffFull patch metadata, worktree isolation, symlink/binary edge cases, cleanup/prune, and concurrency behavior remain deferred",
        "SnapshotSmoke",
        m11Owners.foundation,
      ],
    ],
    [
      "tool/question.test.ts",
      [
        "partial",
        "src/opencodehx/tool/QuestionTool.hx; src/opencodehx/question/QuestionRuntime.hx; src/opencodehx/smoke/ToolSmoke.hx; docs/tool-registry-port.md",
        "question parameter decoding, pending request creation with tool metadata, reply resolution, long-header preservation, formatted output, and answer metadata are covered through the async Haxe question tool facade; registration in the synchronous ToolRegistry/session tool loop remains deferred until async tool execution lands",
        "ToolSmoke.questionExec",
        m11Owners.tool,
      ],
    ],
    [
      "tool/skill.test.ts",
      [
        "partial",
        "src/opencodehx/tool/SkillTool.hx; src/opencodehx/skill/SkillRegistry.hx; src/opencodehx/smoke/ToolSmoke.hx; docs/tool-registry-port.md",
        "skill name decoding, local registry lookup, permission request shape, metadata.dir, skill content block, base-directory file URL, and sampled file list output are covered through the async Haxe skill tool facade; registration in the synchronous ToolRegistry/session tool loop remains deferred until async tool execution lands",
        "ToolSmoke.skillExec",
        m11Owners.tool,
      ],
    ],
    [
      "tool/webfetch.test.ts",
      [
        "partial",
        "src/opencodehx/tool/WebFetchTool.hx; src/opencodehx/smoke/ToolSmoke.hx; docs/tool-registry-port.md",
        "text, SVG text passthrough, and image data-url attachment behavior are covered through the async Haxe webfetch runtime; registration in the synchronous ToolRegistry/session tool loop remains deferred until async tool execution lands",
        "ToolSmoke.webFetchExec",
        m11Owners.tool,
      ],
    ],
    ["pty/pty-output-isolation.test.ts", ["direct", "src/opencodehx/smoke/PtySmoke.hx; docs/pty-runtime.md", "service-level fixtures cover replay, tail cursors, reused socket wrappers, recycled socket objects, and in-place data mutation", "PtySmoke outputReplay/reusedSocketIsolation/recycledSocketIsolation/inPlaceSocketDataMutation", "none"]],
    ["pty/pty-session.test.ts", ["direct", "src/opencodehx/smoke/PtySmoke.hx; src/opencodehx/smoke/ServerSmoke.hx; docs/pty-runtime.md", "created/exited/deleted lifecycle plus PTY HTTP/WebSocket routes are covered; full Effect service integration remains deferred", "PtySmoke lifecycle fixtures plus ServerSmoke PTY routes/WebSocket", "none"]],
    ["pty/pty-shell.test.ts", ["direct", "src/opencodehx/pty/PtyService.hx; src/opencodehx/smoke/PtySmoke.hx; scripts/harness/windows-shell-smoke.mjs; docs/pty-runtime.md", "deterministic smoke covers PowerShell empty args and Git Bash login args; Windows CI smoke repeats the behavior against native shells when available", "PtySmoke ptyShellArgsParity plus windows:shell:smoke", "none"]],
    ["shell/shell.test.ts", ["direct", "src/opencodehx/host/node/NodeProcess.hx; src/opencodehx/smoke/PtySmoke.hx; scripts/harness/windows-shell-smoke.mjs; docs/bash-shell-seam.md", "deterministic smoke covers shell names, login/posix classification, blacklisted Windows shells, Git Bash normalization, /usr/bin/bash Git Bash resolution, and bare PowerShell resolution; Windows CI smoke covers native execution and kill-tree teardown", "PtySmoke shellSelectionParity plus windows:shell:smoke", "none"]],
    ["tool/external-directory.test.ts", ["partial", "src/opencodehx/smoke/ToolSmoke.hx; docs/bash-shell-seam.md; docs/core-file-tools-port.md", "external workdir and wildcard path denial are covered for bash, and canonical external-directory request/denial shape is covered for read file, write file, edit file, apply_patch hunk/move file targets, glob directory, and grep file targets; broader bash argument path variants remain deferred to the bash row", "ToolSmoke bashExec/readExec/writeExec/editExec/applyPatchExec/globExec/grepExec external directory cases"]],
    [
      "tool/registry.test.ts",
      [
        "partial",
        "src/opencodehx/smoke/ToolSmoke.hx; docs/tool-registry-port.md",
        "builtin registry, errors, and .opencode custom tool file discovery are covered; dynamic module import/export mapping and custom tool execution remain deferred",
        "ToolSmoke.registrySurface and registryCustomTools",
      ],
    ],
    ["permission-task.test.ts", ["ported", "src/opencodehx/smoke/PermissionSmoke.hx; docs/permission-model-port.md", "none", "PermissionSmoke.taskPermissionRules"]],
    ["share/share-next.test.ts", ["partial", "src/opencodehx/share/ShareNextRuntime.hx; src/opencodehx/smoke/ShareSmoke.hx; docs/share-next-runtime.md", "ShareNext request routing covers legacy enterprise/default URLs, org-account API paths, typed auth/org headers, missing-token failure, create/remove persistence, request method/URL shape, latest-diff sync coalescing, missing-row removal, and non-OK create failure without persistence; delayed timer scheduling, event subscriptions, disabled-share flags, real database persistence, and live HTTP layer integration remain deferred", "ShareSmoke.requestRouting/createRemovePersistence/syncCoalescing"]],
    [
      "permission/next.test.ts",
      [
        "partial",
        "src/opencodehx/permission/PermissionAsyncRuntime.hx; src/opencodehx/smoke/PermissionSmoke.hx; src/opencodehx/smoke/ServerSmoke.hx; docs/permission-model-port.md",
        "pure rule/config/merge/disabled semantics, sync ask/allow/deny/reject behavior, focused async pending lifecycle, typed scoped/global permission bus publication, and server /permission list/reply routes are covered; database persistence and live async session/tool graph integration remain deferred",
        "PermissionSmoke fromConfigAndEvaluate/mergeAndEvaluate/disabledTools/runtimeAskReply/toolIntegration/runAsync including permission bus publication; ServerSmoke permissionRoutes",
      ],
    ],
    ["permission/arity.test.ts", ["direct", "src/opencodehx/permission/BashArity.hx; src/opencodehx/smoke/PermissionSmoke.hx; docs/permission-model-port.md", "upstream bash arity prefix cases are covered, including unknown commands, arity-1/2/3 commands, longest-match nested prefixes, exact-length matches, and edge cases", "PermissionSmoke.bashArityPrefix", "none"]],
    ["provider/provider.test.ts", ["partial", "src/opencodehx/smoke/ProviderSmoke.hx; src/opencodehx/smoke/AiSdkProviderSmoke.hx; src/opencodehx/smoke/ProviderTransformSmoke.hx; src/opencodehx/smoke/ServerSmoke.hx; docs/provider-registry-port.md", "broader live provider loading, external credential chains, live plugin-loaded auth hooks, and full upstream provider service lifecycle remain deferred", "ProviderSmoke registry/env/config/auth/filter/model fixtures plus AiSdkProviderSmoke factory paths, ProviderTransformSmoke request/message transforms, SessionProcessorSmoke live provider-transform middleware evidence, and ServerSmoke GET /config/providers, GET /provider, GET /provider/auth, plus POST provider OAuth fixtures"]],
    ["provider/amazon-bedrock.test.ts", ["partial", "src/opencodehx/smoke/ProviderSmoke.hx; src/opencodehx/smoke/ProviderTransformSmoke.hx; docs/provider-registry-port.md", "Bedrock credential provider chain internals remain deferred; no-network factory resolution and model-prefix selection are covered", "ProviderSmoke Bedrock config/env/auth/prefix fixtures plus ProviderTransformSmoke Bedrock provider-option/cache/variant fixtures"]],
    ["provider/transform.test.ts", ["partial", "src/opencodehx/provider/ProviderTransform.hx; src/opencodehx/smoke/ProviderTransformSmoke.hx; docs/provider-registry-port.md", "remaining upstream transform cases should still be promoted fixture-by-fixture, especially provider-specific request bodies that require live SDK boundaries", "ProviderTransformSmoke request defaults/providerOptions/params/variants/schema/message transforms plus SessionProcessorSmoke live stream middleware evidence"]],
    ["provider/copilot/convert-to-copilot-messages.test.ts", ["partial", "src/opencodehx/provider/copilot/CopilotChatMessages.hx; src/opencodehx/smoke/CopilotChatMessagesSmoke.hx; docs/provider-registry-port.md", "broader Copilot streaming/provider lifecycle and auth integration remain deferred", "CopilotChatMessagesSmoke prompt conversion fixtures"]],
    ["provider/copilot/copilot-chat-model.test.ts", ["partial", "src/opencodehx/provider/copilot/*; src/opencodehx/smoke/CopilotChatCompletionSmoke.hx; src/opencodehx/smoke/CopilotChatRequestSmoke.hx; src/opencodehx/smoke/CopilotChatLanguageModelSmoke.hx; src/opencodehx/smoke/CopilotResponsesLanguageModelSmoke.hx; docs/provider-registry-port.md", "broader live Copilot credential-backed transport and edge response cases remain deferred", "Copilot chat completion/request/language-model/responses smoke fixtures"]],
    ["provider/gitlab-duo.test.ts", ["partial", "src/opencodehx/provider/AiSdkLanguageLoader.hx; src/opencodehx/smoke/ProviderSmoke.hx; docs/provider-registry-port.md", "credential-backed GitLab Duo live calls remain deferred; static registry/loading behavior is covered", "ProviderSmoke GitLab Duo registry and no-network factory fixtures"]],
    ["cli/account.test.ts", ["direct", "src/opencodehx/cli/AccountDisplay.hx; src/opencodehx/smoke/CliSmoke.hx; docs/cli-command-surface.md", "pure console account display helpers cover account URL labels, active account suffixes, and active org row formatting after ANSI stripping; login/logout/switch/open account service side effects remain deferred", "CliSmoke.accountDisplayFormatting", "none"]],
    ["cli/import.test.ts", ["direct", "src/opencodehx/cli/CliImport.hx; src/opencodehx/smoke/CliSmoke.hx; docs/cli-command-surface.md", "pure import helpers cover share URL slug parsing, invalid URL rejection, same-origin auth-header decisions including default port normalization, and flat share session/message/part transformation; fetch fallback, file import, and database writes remain deferred", "CliSmoke.importShareHelpers", "none"]],
    ["cli/error.test.ts", ["direct", "src/opencodehx/smoke/CliSmoke.hx; fixtures/resources/errors/diagnostics.golden.json; docs/error-diagnostics-parity.md", "current upstream cli/error.test.ts account transport diagnostic is covered; broader yargs/Effect/TUI error taxonomy remains deferred outside this file", "CliSmoke.diagnosticFormatting account transport case", "none"]],
    ["git/git.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; scripts/harness/file-watcher-smoke.mjs; docs/project-runtime-parity.md", "branch/defaultBranch/status/diff/stats, explicit branch-refresh events, and native watcher-backed HEAD branch refresh are covered; broader file service watcher behavior remains deferred", "ProjectRuntimeSmoke Git/VCS fixtures; file-watcher-smoke.mjs", m11Owners.foundation]],
    ["installation/installation.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "installation method detection, latest-version lookup for GitHub/npm/bun/pnpm/brew/scoop/choco shapes, release-type classification, upgrade command planning, and package-manager uninstall command planning are covered with typed injected HTTP/process seams; real package-manager side effects remain deferred", "ProjectRuntimeSmoke installationRuntime fixture", m11Owners.foundation]],
    ["npm.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "package spec sanitizing, package cache add/install/which/outdated semantics, installation package-manager discovery, uninstall command planning, and config dependency bootstrap are covered through typed injected seams; live package-manager side effects remain deferred", "ProjectRuntimeSmoke npmSanitize/npmRuntime/installationRuntime and ConfigSmoke dependencyBootstrap fixtures", m11Owners.foundation]],
    ["project/migrate-global.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "global/no-commit discovery plus storage-backed migration of matching global sessions are covered; fuller database service integration remains deferred", "ProjectRuntimeSmoke projectGlobalMigration fixture", m11Owners.foundation]],
    ["project/project.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; src/opencodehx/smoke/ServerSmoke.hx; docs/project-runtime-parity.md", "project discovery, initGit, stable/cached git-root IDs, clone/bare cache behavior, updates/events, initialization timestamps, command-executed init timestamps, favicon discovery, sandbox pruning, stored command updates, and server project metadata updates are covered; fuller config/service integration remains deferred", "ProjectRuntimeSmoke project edge fixtures plus ServerSmoke PATCH /project/:projectID fixture", m11Owners.foundation]],
    ["project/vcs.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; scripts/harness/file-watcher-smoke.mjs; docs/project-runtime-parity.md", "git repo discovery, core VCS commands, explicit branch-change events, typed bus propagation, HEAD file-update refresh, native watcher-backed HEAD refresh, and git/branch diff modes are covered; broader file watcher service behavior remains deferred", "ProjectRuntimeSmoke VcsRuntime fixture; file-watcher-smoke.mjs", m11Owners.foundation]],
    ["project/worktree-remove.test.ts", ["direct", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "service-level fixtures cover existing/missing removal, branch deletion, sandbox untracking, nonzero git remove after detach, Windows-sensitive path keys, and conditional native Windows fsmonitor cleanup", "ProjectRuntimeSmoke worktree remove/platform failure fixtures", "none"]],
    ["project/worktree.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; docs/project-runtime-parity.md", "worktree slug/unique naming, branch, create, ready/failed events, project-ID sharing, sandbox tracking, typed upstream-order instance service graph, bootstrap/cache/disposal, command-executed initialization, start commands, reset/clean, primary/missing reset errors, and non-git rejection are covered; concrete share/snapshot/live plugin/LSP service internals remain deferred", "ProjectRuntimeSmoke worktree and instance bootstrap graph fixtures", m11Owners.foundation]],
    ["sync/index.test.ts", ["partial", "src/opencodehx/smoke/ProjectRuntimeSmoke.hx; src/opencodehx/smoke/ServerSmoke.hx; docs/project-runtime-parity.md", "typed sequencing, custom aggregate fields, aggregate history, persistence hooks, publish/replay bus behavior, restart-style reload, remove, server replay/history routes, unknown-type errors, and sequence gaps are covered; full SyncEvent definition/projector/database/GlobalBus/payload registry graph remains deferred", "ProjectRuntimeSmoke SyncEventStore fixture plus ServerSmoke /sync routes", m11Owners.foundation]],
    ["control-plane/adaptors.test.ts", ["direct", "src/opencodehx/controlplane/WorkspaceAdaptors.hx; src/opencodehx/smoke/ControlPlaneSmoke.hx; docs/server-hono-seam.md", "typed workspace adaptor registry smoke covers project-scoped isolation, latest registration wins, and list metadata for custom adaptors", "ControlPlaneSmoke workspace adaptor registry fixtures", "none"]],
    ["control-plane/sse.test.ts", ["direct", "src/opencodehx/smoke/ServerSmoke.hx; src/opencodehx/sync/WorkspaceSyncSse.hx; docs/project-runtime-parity.md", "WorkspaceSyncSse parser smoke covers upstream CRLF, multiline JSON data, and non-JSON id/retry fallback behavior", "ServerSmoke WorkspaceSyncSse parser fixtures", "none"]],
    [
      "server/session-list.test.ts",
      [
        "direct",
        "src/opencodehx/smoke/ServerSmoke.hx; docs/server-hono-seam.md",
        "route-level smoke covers upstream directory, root, start, search, and limit filter behavior plus session detail, child-session list, and delete routes",
        "ServerSmoke GET /session filter fixtures plus GET /session/:id, GET /session/:id/children, and DELETE /session/:id fixtures",
        "none",
      ],
    ],
    ["server/global-session-list.test.ts", ["direct", "src/opencodehx/smoke/ServerSmoke.hx; docs/server-hono-seam.md", "route-level smoke covers /experimental/session listing across routed projects, project metadata, cursor pagination, search, and archived-session exclusion/inclusion", "ServerSmoke GET /experimental/session fixtures plus PATCH /session/:id archive fixture", "none"]],
    ["server/project-init-git.test.ts", ["direct", "src/opencodehx/smoke/ServerSmoke.hx; src/opencodehx/project/ProjectRuntime.hx; src/opencodehx/snapshot/SnapshotRuntime.hx; docs/server-hono-seam.md", "route-level smoke covers /project, /project/git/init, /project/current, /project/:projectID PATCH, multi-project list output, project metadata update responses, missing/invalid update errors, git initialization, instance reload/disposed events, no .git/opencode cache creation, already-git no-reload behavior, and server-attached snapshot tracking after reload", "ServerSmoke project list, project update, and git init route fixtures", "none"]],
    [
      "server/session-messages.test.ts",
      [
        "direct",
        "src/opencodehx/smoke/ServerSmoke.hx",
        "message page, cursor header, bad cursor, missing session, message detail, message delete, and high-volume legacy limit behavior are covered",
        "ServerSmoke GET /session/:id/message plus GET/DELETE /session/:id/message/:messageID fixtures",
        "none",
      ],
    ],
    [
      "server/session-actions.test.ts",
      [
        "direct",
        "src/opencodehx/smoke/ServerSmoke.hx; src/opencodehx/server/ServerSessionStatusRuntime.hx; docs/server-hono-seam.md",
        "route-level smoke covers upstream abort action success response, missing-session validation, status event routing, injected live AI SDK active status observation, config-backed live provider/default-agent selection, and active live abort propagation",
        "ServerSmoke POST /session/:id/abort, /session/status, injected live AI SDK /session route, and config-backed live AI SDK /session route",
        "none",
      ],
    ],
    ["server/session-select.test.ts", ["direct", "src/opencodehx/smoke/ServerSmoke.hx; docs/server-hono-seam.md", "route-level smoke covers upstream valid, missing, and invalid select-session outcomes", "ServerSmoke POST /tui/select-session validation fixtures", "none"]],
    ["server/trace-attributes.test.ts", ["direct", "src/opencodehx/server/ServerTrace.hx; src/opencodehx/smoke/ServerSmoke.hx", "trace helper smoke covers ID-shaped route params, non-ID opencode namespace params, http method, and query-stripped path attributes", "ServerSmoke server trace attribute fixture", "none"]],
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
    cli: "CliSmoke and cli-smoke.mjs cover the headless run scaffold, run --file local file/directory attachment parts, default/OPENCODE_DB-backed deterministic/mock/live AI SDK run persistence/export/resume append/continue/fork, non-interactive export <sessionID> JSON/sanitize behavior, first run --session recovery validation, run --continue latest-root selection, and local no-network live run --model provider/model plus plain config-model run OpenAI-compatible streaming success/read-write-edit-apply_patch-bash tool-call continuation/write-then-read tool-chain/config-denied write/permission-skip write/skip-preserved explicit-deny/provider-error persistence",
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
  "**Bead:** `opencodehx-000.1`",
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
  "- `direct`: existing OpenCodeHX executable evidence covers the upstream item's behavior without a separate copied test.",
  "- `partial`: current evidence covers part of the upstream behavior, but the matrix names the missing scope and owning Bead.",
  "- `deferred`: no replacement exists yet because the owning product/runtime slice has not started.",
  "- `reference-only`: upstream fixture/helper/document input, not an executable test. It remains an oracle input for the owning slice.",
  "",
  "Every `partial` or `deferred` executable test row has a `skip_or_defer_reason`, a current or pending `replacement_fixture`, and a `next_bead` owner. Keep this file generated from `scripts/inventory/build-parity-matrix.mjs` so status changes are reviewable instead of drifting into markdown prose.",
  "",
  "## Current Reading",
  "",
  "OpenCodeHX has direct executable evidence in these broad areas:",
  "",
  "- CLI/headless run, export, session persistence, resume/continue/fork, and local no-network live streaming.",
  "- Installed npm package workflows for run, tool calls, persistence, TUI scaffold execution, and server health/SSE/session/PTY routes.",
  "- Utility, config, file, message, storage, tool, permission, provider registry, project/git/worktree/sync/npm, PTY, and one-turn session behavior.",
  "- Credential-free AI SDK stream mechanics, local provider-error handling, tool schema advertisement, and side-effecting live tool-loop evidence.",
  "- Bundled SDK factory paths for OpenAI-compatible, OpenAI, xAI, Azure, Google, Vertex, Anthropic, Bedrock, Mistral, Groq, Cohere, Perplexity, OpenRouter, DeepInfra, Cerebras, Gateway, TogetherAI, Vercel, Alibaba, and GitLab.",
  "- First provider request-option, variant, schema, and plugin-hook evidence.",
  "",
  "Large product surfaces remain deferred:",
  "",
  "- full server/API and SDK compatibility",
  "- broader provider SDK loading and transforms",
  "- full session lifecycle",
  "- MCP/ACP",
  "- plugin loading/install/auth/runtime side effects",
  "- LSP",
  "- live TUI beyond the scaffold",
  "- live package-manager side effects",
  "- Bun/release packaging",
  "",
  "The next practical move is to use this matrix while selecting Beads: before starting a subsystem, filter `reference/opencode-test-port-matrix.csv` by `next_bead` and promote the relevant upstream tests into Haxe-owned fixtures or differential harnesses.",
  "",
].join("\n")

writeFileSync(join(repoRoot, "docs", "opencode-test-port-matrix.md"), portMarkdown)
