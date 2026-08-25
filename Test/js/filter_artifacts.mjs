import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Filter Lab directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "FilterLab.mjs.manifest.json"), "utf8"),
);
if (
  manifest.compilerVersion !== "0.1.0-dev" ||
  manifest.module !== "FilterLab.mjs" ||
  typeof manifest.graphHash !== "string" ||
  manifest.graphHash.length === 0 ||
  manifest.runtimeAbi !== 15 ||
  JSON.stringify(manifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(manifest.stateSlots) !== JSON.stringify(["string"]) ||
  manifest.sourceCount !== 1 ||
  manifest.derivedCount !== 0 ||
  manifest.textSinkCount !== 1 ||
  manifest.eventCount !== 3 ||
  JSON.stringify(manifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs"]) ||
  JSON.stringify(manifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "attr-selections",
  ])
) {
  throw new Error("generated Filter Lab manifest is invalid");
}

const graph = await readFile(path.join(directory, "Filter.graph.json"), "utf8");
for (const required of [
  "\"attr:0:class\"", "\"attr:1:aria-pressed\"", "\"attr:6:disabled\"",
]) {
  if (!graph.includes(required)) {
    throw new Error(`generated Filter Lab graph is missing ${required}`);
  }
}

const source = await readFile(path.join(directory, "FilterLab.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function("]) {
  if (source.includes(banned)) throw new Error(`generated Filter Lab contains ${banned}`);
}
for (const required of [
  // ADR-0045: attribute selections join the commit sweep beside text sinks
  // with the evaluate-compare-write shape and the tx[8]/tx[9] counters.
  "const attrRefs = [node_4, node_4, node_6, node_6, node_8, node_8, node_10];",
  "const attr_next_0 = state[0] === \"all\" ? \"selected\" : \"\";",
  "const attr_next_1 = state[0] === \"all\" ? \"true\" : \"false\";",
  "const attr_next_6 = state[0] === \"all\";",
  "setAttribute(attrRefs[0], \"class\", attr_next_0);",
  "setAttribute(attrRefs[1], \"aria-pressed\", attr_next_1);",
  "setProperty(attrRefs[6], \"disabled\", attr_next_6);",
  // The mount path writes the evaluated initial cache through the same
  // write statements before any event runs.
  "setAttribute(attrRefs[0], \"class\", attrCache[0]);",
  "setProperty(attrRefs[6], \"disabled\", attrCache[6]);",
  "const context = [state, refs, tx, oldSources, changed, sinkCache, attrRefs, attrCache];",
]) {
  if (!source.includes(required)) {
    throw new Error(`generated Filter Lab is missing ${required}`);
  }
}

const generated = await import(pathToFileURL(path.join(directory, "FilterLab.mjs")).href);
if (typeof generated.mount !== "function") {
  throw new Error("generated Filter Lab does not export mount");
}

console.log("generated Filter Lab artifacts passed");
