import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated LeanRx docs directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "LeanRxDocs.mjs.manifest.json"), "utf8"),
);
if (
  manifest.compilerVersion !== "0.1.0-dev" ||
  manifest.leanToolchain !== "leanprover/lean4:v4.33.0" ||
  manifest.module !== "LeanRxDocs.mjs" ||
  typeof manifest.graphHash !== "string" ||
  manifest.graphHash.length === 0 ||
  manifest.runtimeAbi !== 9 ||
  JSON.stringify(manifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(manifest.stateSlots) !==
    JSON.stringify(["int", "string", "string", "string"]) ||
  manifest.sourceCount !== 1 ||
  manifest.derivedCount !== 3 ||
  manifest.textSinkCount !== 3 ||
  manifest.eventCount !== 7 ||
  JSON.stringify(manifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./leanrx_host.mjs"]) ||
  JSON.stringify(manifest.features) !==
    JSON.stringify(["scalar", "events", "transactions", "instrumentation", "trace"])
) {
  throw new Error("generated LeanRx docs manifest is invalid");
}

const source = await readFile(path.join(directory, "LeanRxDocs.mjs"), "utf8");
const index = await readFile(path.join(directory, "index.html"), "utf8");
const graphHtml = await readFile(path.join(directory, "LeanRxDocs.graph.html"), "utf8");
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
