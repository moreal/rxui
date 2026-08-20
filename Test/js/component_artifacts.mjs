import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Counter directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "Counter.mjs.manifest.json"), "utf8"),
);
if (
  manifest.compilerVersion !== "0.1.0-dev" ||
  manifest.leanToolchain !== "leanprover/lean4:v4.33.0" ||
  manifest.module !== "Counter.mjs" ||
  typeof manifest.graphHash !== "string" ||
  manifest.graphHash.length === 0 ||
  manifest.runtimeAbi !== 7 ||
  JSON.stringify(manifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(manifest.stateSlots) !== JSON.stringify(["int", "int", "string"]) ||
  manifest.sourceCount !== 1 ||
  manifest.derivedCount !== 2 ||
  manifest.textSinkCount !== 5 ||
  manifest.eventCount !== 4 ||
  JSON.stringify(manifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./leanrx_host.mjs"]) ||
  JSON.stringify(manifest.features) !==
    JSON.stringify(["scalar", "events", "transactions", "instrumentation", "trace"])
) {
  throw new Error("generated Counter manifest is invalid");
}

const source = await readFile(path.join(directory, "Counter.mjs"), "utf8");
const declarations = await readFile(path.join(directory, "Counter.generated.lean"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function("]) {
  if (source.includes(banned)) throw new Error(`generated Counter contains ${banned}`);
}
if (!declarations.includes("namespace LeanRxGenerated.Counter") ||
    !declarations.includes("CounterSyntax_declarations") ||
    !declarations.includes("CounterSyntax_check")) {
  throw new Error("generated Counter editor declarations are invalid");
}

const generated = await import(pathToFileURL(path.join(directory, "Counter.mjs")).href);
if (typeof generated.mount !== "function") {
  throw new Error("generated Counter does not export mount");
}

console.log("generated Counter artifacts passed");
