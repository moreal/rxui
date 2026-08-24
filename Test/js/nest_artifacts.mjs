import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Nest Lab directory");

const nestManifest = JSON.parse(
  await readFile(path.join(directory, "NestLab.mjs.manifest.json"), "utf8"),
);
if (
  nestManifest.compilerVersion !== "0.1.0-dev" ||
  nestManifest.module !== "NestLab.mjs" ||
  typeof nestManifest.graphHash !== "string" ||
  nestManifest.graphHash.length === 0 ||
  nestManifest.runtimeAbi !== 15 ||
  JSON.stringify(nestManifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(nestManifest.stateSlots) !== JSON.stringify(["int"]) ||
  nestManifest.sourceCount !== 1 ||
  nestManifest.derivedCount !== 0 ||
  nestManifest.textSinkCount !== 1 ||
  nestManifest.eventCount !== 1 ||
  JSON.stringify(nestManifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./Pulse.mjs"]) ||
  JSON.stringify(nestManifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "child-components",
  ])
) {
  throw new Error("generated Nest Lab manifest is invalid");
}

const pulseManifest = JSON.parse(
  await readFile(path.join(directory, "Pulse.mjs.manifest.json"), "utf8"),
);
if (
  pulseManifest.module !== "Pulse.mjs" ||
  JSON.stringify(pulseManifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs"]) ||
  JSON.stringify(pulseManifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
  ])
) {
  throw new Error("generated Pulse manifest is invalid");
}

const nestSource = await readFile(path.join(directory, "NestLab.mjs"), "utf8");
const pulseSource = await readFile(path.join(directory, "Pulse.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function("]) {
  if (nestSource.includes(banned) || pulseSource.includes(banned)) {
    throw new Error(`generated Nest Lab contains ${banned}`);
  }
}
for (const required of [
  "import { mount as $lrx_child_0 } from \"./Pulse.mjs\";",
  "const child_off_0 = $lrx_child_0(node_0);",
  "makeDisposer(node_0, [child_off_0, off_0], tx)",
]) {
  if (!nestSource.includes(required)) {
    throw new Error(`generated Nest Lab is missing ${required}`);
  }
}
if (pulseSource.includes("$lrx_child") || pulseSource.includes("Pulse.mjs")) {
  throw new Error("generated Pulse module unexpectedly nests children");
}

const generated = await import(pathToFileURL(path.join(directory, "NestLab.mjs")).href);
if (typeof generated.mount !== "function") {
  throw new Error("generated Nest Lab does not export mount");
}

console.log("generated Nest Lab artifacts passed");
