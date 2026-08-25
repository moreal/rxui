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
  JSON.stringify(nestManifest.stateSlots) !== JSON.stringify(["int", "int"]) ||
  nestManifest.sourceCount !== 2 ||
  nestManifest.derivedCount !== 0 ||
  nestManifest.textSinkCount !== 1 ||
  nestManifest.eventCount !== 2 ||
  JSON.stringify(nestManifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./leanrx_region.mjs", "./Pulse.mjs"]) ||
  JSON.stringify(nestManifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "child-components", "keyed-regions",
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
    "immutable-props",
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
  "import { createKeyedRegion } from \"./leanrx_region.mjs\";",
  "const child_off_0 = $lrx_child_0(node_0, [\"Pulse child\"]);",
  "const region_0 = createKeyedRegion(node_9, $lrx_region_0_row, $lrx_region_0_update, $lrx_region_0_dispose);",
  "const region_off_0 = listenDelegatedCells(node_9, \"click\", state, context, $lrx_region_0_dispatch, [\"\", \"mark\", \"remove\"]);",
  "regions[0][1][\"push\"]([regions[0][2], $lrx_event_1_append_0_0(state[0], state[1]), $lrx_event_1_append_0_1(state[0], state[1])]);",
  "setKey(row_0, item[0]);",
  "const regions = [[region_0, [], 0, false, []]];",
  // ADR-0043: the mark dispatch mutates the retained item in place and the
  // commit sweep drains exactly the pending positions through updateAt.
  "const row_next_0 = row_item[2] + \" ★\";",
  "regions[0][4][\"push\"](scan[1]);",
  "regions[0][0][\"updateAt\"](pending_row, regions[0][1][pending_row], null);",
  // ADR-0043/0044: the retained-row update callback re-renders the sealed
  // expression text and the class selection by structural navigation.
  "function $lrx_region_0_update(row, item, position, context) {",
  "  setAttribute(row, \"class\", item[2] === \"\" ? \"roster-row\" : \"roster-row marked\");",
  "  setText(childAt(childAt(row, 0), 0), item[1] + item[2]);",
  "makeDisposer(node_0, [child_off_0, off_0, off_1, region_off_0, region_0[\"dispose\"]], tx, [region_0])",
]) {
  if (!nestSource.includes(required)) {
    throw new Error(`generated Nest Lab is missing ${required}`);
  }
}
for (const required of [
  "function mount(target, props)",
  "createText(props[0])",
]) {
  if (!pulseSource.includes(required)) {
    throw new Error(`generated Pulse is missing ${required}`);
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
