import {readFileSync, readdirSync, statSync, writeFileSync} from "node:fs"
import {join, relative} from "node:path"

const root = new URL("../..", import.meta.url).pathname
const baselinePath = join(root, "reference", "typed-boundary-baseline.json")
const update = process.argv.includes("--update-baseline")

const patterns = [
  ["Dynamic", /\bDynamic\b/g],
  ["DynamicAccess", /\bDynamicAccess\b/g],
  ["cast", /\bcast\b/g],
  ["untyped", /\buntyped\b/g],
  ["Syntax.code", /Syntax\.code/g],
  ["@:ts.type", /@:ts\.type/g],
  ["Reflect.field", /Reflect\.field/g],
  ["Reflect.hasField", /Reflect\.hasField/g],
  ["Reflect.setField", /Reflect\.setField/g],
  ["Any", /\bAny\b/g],
]

const sourceRoots = ["src/opencodehx"]

function haxeFiles(dir) {
  const out = []
  for (const name of readdirSync(dir)) {
    const path = join(dir, name)
    const stat = statSync(path)
    if (stat.isDirectory()) out.push(...haxeFiles(path))
    else if (name.endsWith(".hx")) out.push(path)
  }
  return out
}

function scan() {
  const files = {}
  const totals = Object.fromEntries(patterns.map(([name]) => [name, 0]))
  for (const sourceRoot of sourceRoots) {
    for (const file of haxeFiles(join(root, sourceRoot))) {
      const text = readFileSync(file, "utf8")
      const counts = {}
      for (const [name, pattern] of patterns) {
        const count = (text.match(pattern) ?? []).length
        if (count > 0) {
          counts[name] = count
          totals[name] += count
        }
      }
      if (Object.keys(counts).length > 0) files[relative(root, file)] = counts
    }
  }
  return {patterns: patterns.map(([name]) => name), sourceRoots, totals, files}
}

function readBaseline() {
  try {
    return JSON.parse(readFileSync(baselinePath, "utf8"))
  } catch (error) {
    console.error(`typed-boundary baseline missing or invalid: ${baselinePath}`)
    console.error("Run: node scripts/ci/typed-boundary-scan.mjs --update-baseline")
    process.exit(1)
  }
}

function totalCount(counts) {
  return Object.values(counts).reduce((sum, count) => sum + count, 0)
}

const current = scan()

if (update) {
  writeFileSync(
    baselinePath,
    `${JSON.stringify({
      generatedBy: "scripts/ci/typed-boundary-scan.mjs --update-baseline",
      note: "Budgets are maximum accepted weak-type marker counts. Reductions pass; increases require narrowing or a deliberate baseline update with documentation.",
      ...current,
    }, null, 2)}\n`,
  )
  console.log(`updated ${relative(root, baselinePath)} (${Object.keys(current.files).length} files, ${totalCount(current.totals)} markers)`)
  process.exit(0)
}

const baseline = readBaseline()
const failures = []

for (const [file, counts] of Object.entries(current.files)) {
  const expected = baseline.files[file]
  if (expected == null) {
    failures.push(`${file}: new weak-type markers ${JSON.stringify(counts)}`)
    continue
  }
  for (const [name, count] of Object.entries(counts)) {
    const budget = expected[name] ?? 0
    if (count > budget) failures.push(`${file}: ${name} count ${count} exceeds baseline ${budget}`)
  }
}

for (const [file, counts] of Object.entries(baseline.files)) {
  if (current.files[file] == null && totalCount(counts) > 0) continue
  const currentCounts = current.files[file] ?? {}
  for (const name of baseline.patterns) {
    if ((currentCounts[name] ?? 0) > (counts[name] ?? 0)) {
      failures.push(`${file}: ${name} count ${(currentCounts[name] ?? 0)} exceeds baseline ${(counts[name] ?? 0)}`)
    }
  }
}

if (failures.length > 0) {
  console.error("typed-boundary scan failed:")
  for (const failure of failures) console.error(`- ${failure}`)
  process.exit(1)
}

const baselineTotal = totalCount(baseline.totals)
const currentTotal = totalCount(current.totals)
console.log(`typed-boundary scan passed (${currentTotal}/${baselineTotal} accepted markers)`)
