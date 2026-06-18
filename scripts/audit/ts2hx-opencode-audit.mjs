import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import ts from "typescript";

const repoRoot = path.resolve(import.meta.dirname, "../..");
const sourceRoot = path.resolve(repoRoot, "../opencode/packages/opencode/src");
const outPath = path.join(repoRoot, "reference/ts2hx-opencode-audit.json");

const features = new Map();
const imports = new Map();
const unsupported = new Map();

function add(map, key, file) {
  const item = map.get(key) ?? { count: 0, files: [] };
  item.count++;
  if (item.files.length < 8 && !item.files.includes(file)) item.files.push(file);
  map.set(key, item);
}

function walk(dir, out = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (/\.(ts|tsx)$/.test(entry.name)) out.push(full);
  }
  return out;
}

function rel(file) {
  return path.relative(sourceRoot, file).replaceAll(path.sep, "/");
}

function stringLiteralText(node) {
  return ts.isStringLiteralLike(node) ? node.text : null;
}

function classifyImport(spec) {
  if (spec.startsWith(".")) return "relative";
  if (spec.startsWith("@/")) return "alias:@";
  if (spec.startsWith("@tui/")) return "alias:@tui";
  if (spec.startsWith("@test/")) return "alias:@test";
  if (spec.startsWith("#")) return "alias:#";
  if (spec.startsWith("node:")) return "node-builtin";
  return "npm";
}

function resourceKind(spec) {
  const clean = spec.split("?")[0];
  const ext = path.extname(clean);
  if ([".txt", ".json", ".wav", ".wasm"].includes(ext)) return ext.slice(1);
  return null;
}

function visit(node, file, source) {
  switch (node.kind) {
    case ts.SyntaxKind.InterfaceDeclaration:
      add(features, "interface", file);
      break;
    case ts.SyntaxKind.TypeAliasDeclaration:
      add(features, "type-alias", file);
      break;
    case ts.SyntaxKind.EnumDeclaration:
      add(features, "enum", file);
      break;
    case ts.SyntaxKind.ClassDeclaration:
      add(features, "class", file);
      break;
    case ts.SyntaxKind.JsxElement:
    case ts.SyntaxKind.JsxSelfClosingElement:
    case ts.SyntaxKind.JsxFragment:
      add(features, "tsx-jsx", file);
      add(unsupported, "tsx-jsx-requires-hxx-or-tsx-compiler-fixtures", file);
      break;
    case ts.SyntaxKind.SatisfiesExpression:
      add(features, "satisfies", file);
      add(unsupported, "satisfies-needs-type-directed-haxe-modeling", file);
      break;
    case ts.SyntaxKind.AsExpression:
      add(features, "as-cast", file);
      break;
    case ts.SyntaxKind.NonNullExpression:
      add(features, "non-null-assertion", file);
      break;
    case ts.SyntaxKind.ConditionalType:
      add(features, "conditional-type", file);
      add(unsupported, "advanced-type-level-ts-manual-or-extern", file);
      break;
    case ts.SyntaxKind.MappedType:
      add(features, "mapped-type", file);
      add(unsupported, "advanced-type-level-ts-manual-or-extern", file);
      break;
    case ts.SyntaxKind.TemplateLiteralType:
      add(features, "template-literal-type", file);
      add(unsupported, "advanced-type-level-ts-manual-or-extern", file);
      break;
    case ts.SyntaxKind.ImportType:
      add(features, "import-type", file);
      break;
    default:
      break;
  }

  if (ts.isImportDeclaration(node)) {
    const spec = stringLiteralText(node.moduleSpecifier);
    if (spec) {
      add(imports, classifyImport(spec), file);
      const resource = resourceKind(spec);
      if (resource) {
        add(imports, `resource:${resource}`, file);
        if (resource !== "json") add(unsupported, `resource-${resource}-needs-copy-or-loader`, file);
      }
      if (node.importClause?.isTypeOnly) add(imports, "type-only-import", file);
      if (node.attributes && node.attributes.elements.length > 0) add(imports, "import-attributes", file);
    }
  }

  if (ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword) {
    add(imports, "dynamic-import", file);
    if (node.arguments.length > 1) add(imports, "dynamic-import-attributes", file);
  }

  if (ts.isPropertyAccessExpression(node) && node.questionDotToken) add(features, "optional-chaining", file);
  if (ts.isElementAccessExpression(node) && node.questionDotToken) add(features, "optional-chaining", file);
  if (ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.QuestionQuestionToken)
    add(features, "nullish-coalescing", file);
  if (ts.isSpreadAssignment(node) || ts.isSpreadElement(node)) add(features, "spread", file);
  if (ts.isParameter(node) && node.dotDotDotToken) add(features, "rest-parameter", file);
  if (ts.isFunctionLike(node) && node.typeParameters?.length) add(features, "generic-function", file);
  if (ts.isTypeReferenceNode(node) && node.typeArguments?.length) add(features, "generic-type-reference", file);

  ts.forEachChild(node, (child) => visit(child, file, source));
}

const files = walk(sourceRoot).sort();
for (const abs of files) {
  const file = rel(abs);
  const text = readFileSync(abs, "utf8");
  const kind = abs.endsWith(".tsx") ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
  const source = ts.createSourceFile(abs, text, ts.ScriptTarget.Latest, true, kind);
  if (abs.endsWith(".tsx")) add(features, "tsx-file", file);
  visit(source, file, source);
}

function sortedObject(map) {
  return Object.fromEntries([...map.entries()].sort(([a], [b]) => a.localeCompare(b)));
}

const result = {
  schema: "opencodehx.reference.ts2hx-audit.v1",
  sourceRoot: "../opencode/packages/opencode/src",
  sourceFiles: files.length,
  generatedAt: new Date().toISOString(),
  directTs2hxProbe: {
    command: "yarn --cwd ../genes/tools/ts2hx build && node ../genes/tools/ts2hx/dist/cli.js --project ../opencode/packages/opencode/tsconfig.json --list-files --diagnostics",
    result: "failed-before-emit",
    diagnostic: "File '@tsconfig/bun/tsconfig.json' not found."
  },
  features: sortedObject(features),
  imports: sortedObject(imports),
  unsupportedOrManual: sortedObject(unsupported)
};

writeFileSync(outPath, JSON.stringify(result, null, 2) + "\n");
console.log(`Wrote ${path.relative(repoRoot, outPath)}`);
