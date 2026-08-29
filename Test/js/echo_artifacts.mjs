import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Echo Lab directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "EchoLab.mjs.manifest.json"), "utf8"),
);
if (
  manifest.compilerVersion !== "0.1.0-dev" ||
  manifest.module !== "EchoLab.mjs" ||
  typeof manifest.graphHash !== "string" ||
  manifest.graphHash.length === 0 ||
  manifest.runtimeAbi !== 20 ||
  JSON.stringify(manifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(manifest.stateSlots) !==
    JSON.stringify(["string", "string", "string", "bool", "string"]) ||
  manifest.sourceCount !== 4 ||
  manifest.derivedCount !== 1 ||
  manifest.textSinkCount !== 4 ||
  manifest.eventCount !== 6 ||
  JSON.stringify(manifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./leanrx_form_events.mjs"]) ||
  JSON.stringify(manifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "typed-events", "controlled-props",
  ])
) {
  throw new Error("generated Echo Lab manifest is invalid");
}

const source = await readFile(path.join(directory, "EchoLab.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function("]) {
  if (source.includes(banned)) throw new Error(`generated Echo Lab contains ${banned}`);
}
for (const required of [
  "setProperty } from \"./leanrx_dom.mjs\";",
  "import { listenValue, listenKey, listenChecked, listenSubmit } from \"./leanrx_form_events.mjs\";",
  "listenSubmit(node_3, context, null, $lrx_event_1)",
  "listenValue(node_4, \"input\", state, context, $lrx_typed_event_0)",
  "listenKey(node_4, \"keydown\", state, context, $lrx_typed_event_1)",
  "listenChecked(node_5, \"change\", state, context, $lrx_typed_event_3)",
  "listenValue(node_8, \"change\", state, context, $lrx_typed_event_2)",
  "setProperty(propRefs[0], \"value\", propCache[0])",
  "setProperty(propRefs[1], \"checked\", propCache[1])",
  "setProperty(propRefs[2], \"value\", propCache[2])",
]) {
  if (!source.includes(required)) {
    throw new Error(`generated Echo Lab is missing ${required}`);
  }
}

const generated = await import(pathToFileURL(path.join(directory, "EchoLab.mjs")).href);
if (typeof generated.mount !== "function") {
  throw new Error("generated Echo Lab does not export mount");
}

console.log("generated Echo Lab artifacts passed");
