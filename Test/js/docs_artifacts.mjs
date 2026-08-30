import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated LeanRx docs directory");

async function markdownFiles(root) {
  const result = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    const target = path.join(root, entry.name);
    if (entry.isDirectory()) result.push(...await markdownFiles(target));
    else if (entry.isFile() && entry.name.endsWith(".md")) result.push(target);
  }
  return result;
}

const manifest = JSON.parse(
  await readFile(path.join(directory, "LeanRxDocs.mjs.manifest.json"), "utf8"),
);
if (
  manifest.compilerVersion !== "0.1.0-dev" ||
  manifest.leanToolchain !== "leanprover/lean4:v4.33.0" ||
  manifest.module !== "LeanRxDocs.mjs" ||
  typeof manifest.graphHash !== "string" ||
  manifest.graphHash.length === 0 ||
  manifest.runtimeAbi !== 20 ||
  JSON.stringify(manifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(manifest.stateSlots) !==
    JSON.stringify(["string", "string", "string", "string", "string", "string", "string"]) ||
  manifest.sourceCount !== 1 ||
  manifest.derivedCount !== 6 ||
  manifest.textSinkCount !== 6 ||
  manifest.eventCount !== 7 ||
  JSON.stringify(manifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs"]) ||
  JSON.stringify(manifest.features) !==
    JSON.stringify([
      "scalar",
      "events",
      "transactions",
      "instrumentation",
      "trace",
      "attr-selections",
    ])
) {
  throw new Error("generated LeanRx docs manifest is invalid");
}

const source = await readFile(path.join(directory, "LeanRxDocs.mjs"), "utf8");
const index = await readFile(path.join(directory, "index.html"), "utf8");
const graphHtml = await readFile(path.join(directory, "LeanRxDocs.graph.html"), "utf8");
const styles = await readFile(path.join(directory, "styles.css"), "utf8");
const stylesInput = await readFile(path.join(directory, "LeanRxDocs.input.css"), "utf8");
const docsManifest = JSON.parse(
  await readFile(path.join(directory, "leanrx-docs.json"), "utf8"),
);
const declarations = await readFile(
  path.join(directory, "LeanRxDocs.generated.lean"),
  "utf8",
);
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function(", "innerHTML"]) {
  if (source.includes(banned)) throw new Error(`generated LeanRx docs contains ${banned}`);
}
if (!index.startsWith("<!doctype html>") ||
    !index.includes('import { mount } from "./LeanRxDocs.mjs"') ||
    index.includes("innerHTML")) {
  throw new Error("LeanRx docs production shell is invalid");
}
if (!graphHtml.startsWith("<!doctype html>") ||
    !graphHtml.includes("Certified schedule") ||
    graphHtml.includes("<script")) {
  throw new Error("LeanRx docs graph viewer is invalid");
}
for (const utility of [
  ".bg-primary",
  ".grid-cols-2",
  ".rounded-xl",
  ".text-balance",
  ".lg\\:grid-cols-\\[16rem_minmax\\(0\\,1fr\\)\\]",
]) {
  if (!styles.includes(utility)) {
    throw new Error(`Tailwind docs stylesheet lost ${utility}`);
  }
}
if (!stylesInput.includes('@import "tailwindcss" source(none)') ||
    !stylesInput.includes('@source "../LeanRx/Docs/Framework.lean"') ||
    styles.includes("@tailwind")) {
  throw new Error("Tailwind docs input or compiled output is invalid");
}
if (docsManifest.framework !== "LeanRx.Docs" ||
    docsManifest.styling !== "Tailwind CSS 4.3.3" ||
    docsManifest.shadcnDirectCompatibility !== false ||
    docsManifest.markdownExport !== true) {
  throw new Error("LeanRx docs framework metadata is invalid");
}
for (const markdown of [
  "getting-started.md",
  "philosophy.md",
  "components.md",
  "integrations.md",
  "language.md",
  "backend-support.md",
  "trust-model.md",
]) {
  const source = await readFile(path.join(directory, "docs", "guides", markdown), "utf8");
  if (!source.startsWith("# ") || source.length < 500) {
    throw new Error(`LeanRx docs Markdown export is invalid: ${markdown}`);
  }
}
const dogfood = await readFile(path.join(directory, "DOGFOOD.md"), "utf8");
if (!dogfood.startsWith("# Dogfood log") || dogfood.length < 1000) {
  throw new Error("LeanRx docs DOGFOOD export is invalid");
}
for (const markdown of await markdownFiles(directory)) {
  const source = await readFile(markdown, "utf8");
  const links = source.matchAll(/\]\((?!https?:|mailto:|#)([^)#]+\.md)(?:#[^)]*)?\)/g);
  for (const [, href] of links) {
    await readFile(path.resolve(path.dirname(markdown), href), "utf8");
  }
}
const gettingStartedPath = path.join(directory, "docs", "guides", "getting-started.md");
const gettingStarted = await readFile(gettingStartedPath, "utf8");
for (const href of ["language.md", "backend-support.md", "trust-model.md"]) {
  if (!gettingStarted.includes(`](${href})`)) {
    throw new Error(`Getting Started lost its ${href} link`);
  }
  await readFile(path.resolve(path.dirname(gettingStartedPath), href), "utf8");
}
const philosophy = await readFile(
  path.join(directory, "docs", "guides", "philosophy.md"),
  "utf8",
);
if (!philosophy.includes("../../DOGFOOD.md")) {
  throw new Error("Philosophy lost its exported DOGFOOD link");
}
if (!declarations.includes("namespace LeanRxGenerated.Docs") ||
    !declarations.includes("LeanRxDocsSyntax_declarations") ||
    !declarations.includes("LeanRxDocsSyntax_check")) {
  throw new Error("generated LeanRx docs editor declarations are invalid");
}

const generated = await import(pathToFileURL(path.join(directory, "LeanRxDocs.mjs")).href);
if (typeof generated.mount !== "function") {
  throw new Error("generated LeanRx docs does not export mount");
}

console.log("generated LeanRx docs artifacts passed");
