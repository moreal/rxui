import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated TodoMVC directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "TodoMVC.mjs.manifest.json"), "utf8"),
);
if (
  manifest.module !== "TodoMVC.mjs" ||
  manifest.runtimeAbi !== 12 ||
  JSON.stringify(manifest.stateSlots) !== JSON.stringify([
    "list<record<TodoItem>>", "nat", "string", "int", "string", "string",
  ]) ||
  manifest.sourceCount !== 6 ||
  manifest.derivedCount !== 0 ||
  manifest.eventCount !== 10 ||
  !manifest.features.includes("keyed") ||
  !manifest.features.includes("conditional") ||
  !manifest.features.includes("positional") ||
  !manifest.features.includes("reference-propagation") ||
  manifest.features.includes("actual-change") ||
  !manifest.hostImports.includes("./leanrx_form_events.mjs") ||
  !manifest.hostImports.includes("./leanrx_region.mjs") ||
  !manifest.hostImports.includes("./leanrx_unkeyed_region.mjs")
) {
  throw new Error("generated TodoMVC manifest is invalid");
}

const source = await readFile(path.join(directory, "TodoMVC.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function(", "innerHTML"]) {
  if (source.includes(banned)) throw new Error(`generated TodoMVC contains ${banned}`);
}
for (const required of [
  "createKeyedRegion", "createConditionalRegion", "createPositionalRegion",
  "listenDelegated", "data-lrx-action", "data-lrx-key",
]) {
  if (!source.includes(required)) throw new Error(`generated TodoMVC lost ${required}`);
}

const generated = await import(pathToFileURL(path.join(directory, "TodoMVC.mjs")).href);
if (JSON.stringify(Object.keys(generated)) !== JSON.stringify(["mount"])) {
  throw new Error("TodoMVC exposed internal handlers");
}

console.log("generated TodoMVC artifacts passed");
