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
  nestManifest.runtimeAbi !== 17 ||
  JSON.stringify(nestManifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(nestManifest.stateSlots) !== JSON.stringify(["int", "int"]) ||
  nestManifest.sourceCount !== 2 ||
  nestManifest.derivedCount !== 0 ||
  nestManifest.textSinkCount !== 1 ||
  nestManifest.eventCount !== 2 ||
  JSON.stringify(nestManifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./leanrx_region.mjs", "./Chip.mjs", "./Pulse.mjs"]) ||
  JSON.stringify(nestManifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "child-components", "keyed-regions", "row-child-components",
    "typed-row-events",
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
    JSON.stringify(["./leanrx_dom.mjs", "./Tick.mjs"]) ||
  JSON.stringify(pulseManifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "child-components", "immutable-props",
  ])
) {
  throw new Error("generated Pulse manifest is invalid");
}

const tickManifest = JSON.parse(
  await readFile(path.join(directory, "Tick.mjs.manifest.json"), "utf8"),
);
if (
  tickManifest.module !== "Tick.mjs" ||
  JSON.stringify(tickManifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./Blip.mjs", "./Chip.mjs"]) ||
  JSON.stringify(tickManifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "child-components", "immutable-props",
  ])
) {
  throw new Error("generated Tick manifest is invalid");
}

const blipManifest = JSON.parse(
  await readFile(path.join(directory, "Blip.mjs.manifest.json"), "utf8"),
);
if (
  blipManifest.module !== "Blip.mjs" ||
  JSON.stringify(blipManifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs"]) ||
  JSON.stringify(blipManifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "immutable-props",
  ])
) {
  throw new Error("generated Blip manifest is invalid");
}

const chipManifest = JSON.parse(
  await readFile(path.join(directory, "Chip.mjs.manifest.json"), "utf8"),
);
if (
  chipManifest.module !== "Chip.mjs" ||
  JSON.stringify(chipManifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs"]) ||
  JSON.stringify(chipManifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "immutable-props",
  ])
) {
  throw new Error("generated Chip manifest is invalid");
}

const nestSource = await readFile(path.join(directory, "NestLab.mjs"), "utf8");
const pulseSource = await readFile(path.join(directory, "Pulse.mjs"), "utf8");
const tickSource = await readFile(path.join(directory, "Tick.mjs"), "utf8");
const blipSource = await readFile(path.join(directory, "Blip.mjs"), "utf8");
const chipSource = await readFile(path.join(directory, "Chip.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function("]) {
  if (nestSource.includes(banned) || pulseSource.includes(banned) ||
      tickSource.includes(banned) || blipSource.includes(banned) ||
      chipSource.includes(banned)) {
    throw new Error(`generated Nest Lab contains ${banned}`);
  }
}
for (const required of [
  // ADR-0075: the child table serves both scopes — the row-composed Chip and
  // the view-composed Pulse share one aliased-import convention, ordered by
  // first occurrence (the region item precedes the view item).
  "import { mount as $lrx_child_0 } from \"./Chip.mjs\";",
  "import { mount as $lrx_child_1 } from \"./Pulse.mjs\";",
  "import { createKeyedRegion } from \"./leanrx_region.mjs\";",
  "const child_off_0 = $lrx_child_1(node_0, [\"Pulse child\"]);",
  "const region_0 = createKeyedRegion(node_9, $lrx_region_0_row, $lrx_region_0_update, $lrx_region_0_dispose);",
  // ADR-0046: one structural delegated listener per bound event kind, each
  // with its own per-cell action array, sharing one dispatch function.
  "const region_off_0 = listenDelegatedCells(node_9, \"click\", state, context, $lrx_region_0_dispatch, [\"\", \"\", \"\", \"mark\", \"remove\", \"\"]);",
  "const region_off_0_input = listenDelegatedCells(node_9, \"input\", state, context, $lrx_region_0_dispatch, [\"\", \"\", \"rename\", \"\", \"\", \"\"]);",
  "const region_off_0_keydown = listenDelegatedCells(node_9, \"keydown\", state, context, $lrx_region_0_dispatch, [\"\", \"\", \"record\", \"\", \"\", \"\"]);",
  "regions[0][1][\"push\"]([regions[0][2], $lrx_event_1_append_0_0(state[0], state[1]), $lrx_event_1_append_0_1(state[0], state[1]), $lrx_event_1_append_0_2(state[0], state[1]), $lrx_event_1_append_0_3(state[0], state[1])]);",
  "setKey(row_0, item[0]);",
  "const regions = [[region_0, [], 0, false, [], childInventory]];",
  // ADR-0043: the mark dispatch mutates the retained item in place and the
  // commit sweep drains exactly the pending positions through updateAt.
  "const row_next_0 = row_item[2] + \" ★\";",
  "regions[0][4][\"push\"](scan[1]);",
  "regions[0][0][\"updateAt\"](pending_row, regions[0][1][pending_row], regions[0][5]);",
  // ADR-0046: typed row payloads lower to the delegated value/key argument
  // selected by the template binding kind.
  "if (action === \"rename\") {",
  "      const row_next_0 = value;",
  "      const row_next_0 = \"key:\" + eventKey;",
  // ADR-0043/0044: the retained-row update callback re-renders the sealed
  // expression texts and the class selection by structural navigation.
  "function $lrx_region_0_update(row, item, position, context) {",
  "  setAttribute(row, \"class\", item[2] === \"\" ? \"roster-row\" : \"roster-row marked\");",
  "  setText(childAt(childAt(row, 0), 0), item[1] + item[2]);",
  "  setText(childAt(childAt(row, 1), 0), item[3]);",
  "makeDisposer(node_0, [child_off_0, off_0, off_1, region_off_0, region_off_0_input, region_off_0_keydown, region_0[\"dispose\"]], tx, [region_0])",
  // ADR-0075: the row mount callback mounts the row-scoped child at its cell
  // with the projected origin field, stashes the mount return on the row root
  // for the dispose callback, and pushes it into the live inventory the
  // region call sites pass as context. ADR-0089: the stash is a list even at
  // one child, and the dispose callback loops over it — the single-child
  // region is now the one-element case of the general shape, not a shape of
  // its own.
  "const row_child_0 = $lrx_child_0(row_0, [item[4]]);",
  "context[\"push\"](row_child_0);",
  "row_0[\"$lrxRowChild\"] = [row_child_0];",
  "function $lrx_region_0_dispose(row, key, context) {\n  for (const row_child of row[\"$lrxRowChild\"]) {\n    if (context) {\n      context[\"splice\"](context[\"indexOf\"](row_child), 1);\n    }\n    row_child();\n  }\n  return null;\n}",
  // ADR-0066/0075: the disposer republishes the live inventory — the static
  // Pulse disposer seeded first, then one entry per mounted row.
  "const childInventory = [child_off_0];",
  "disposer[\"children\"] = childInventory;",
]) {
  if (!nestSource.includes(required)) {
    throw new Error(`generated Nest Lab is missing ${required}`);
  }
}
for (const required of [
  "function mount(target, props)",
  "createText(props[0])",
  // ADR-0067: the intermediate module composes its own child through the
  // same aliased-import convention and republishes the grandchild mount
  // return on its own disposer, so `children[0].children[0]` reaches the
  // grandchild from the root disposer with no new vocabulary.
  "import { mount as $lrx_child_0 } from \"./Tick.mjs\";",
  // ADR-0068: `label={title}` forwards the parent's own immutable prop —
  // the nested mount call reads the parent's positional mount argument
  // instead of a sealed literal, still a mount-time constant.
  "const child_off_0 = $lrx_child_0(node_0, [props[0]]);",
  "disposer[\"children\"] = [child_off_0];",
]) {
  if (!pulseSource.includes(required)) {
    throw new Error(`generated Pulse is missing ${required}`);
  }
}
for (const required of [
  "function mount(target, props)",
  "createText(props[0])",
  // ADR-0069: re-forwarding is transitive with no new vocabulary — the
  // module that received its prop by forwarding forwards it again through
  // exactly the ADR-0068 call shape, reading its own positional mount
  // argument. ADR-0070: the same received prop fans out into two leaves —
  // one aliased import, one forwarded call, and one disposer entry per
  // child, all in declaration order. ADR-0071: composing the same child
  // module twice reuses the one aliased import while each reference keeps
  // its own mount call, its own prop list (one forward, one literal), and
  // its own disposer entry.
  "import { mount as $lrx_child_0 } from \"./Blip.mjs\";",
  "import { mount as $lrx_child_1 } from \"./Chip.mjs\";",
  "const child_off_0 = $lrx_child_0(node_0, [props[0]]);",
  "const child_off_1 = $lrx_child_1(node_0, [props[0]]);",
  "const child_off_2 = $lrx_child_1(node_0, [\"fixed chip\"]);",
  "disposer[\"children\"] = [child_off_0, child_off_1, child_off_2];",
]) {
  if (!tickSource.includes(required)) {
    throw new Error(`generated Tick is missing ${required}`);
  }
}
// ADR-0071: the child table dedups by module name, so the second Chip
// reference never allocates a third aliased import.
if (tickSource.includes("$lrx_child_2")) {
  throw new Error("generated Tick duplicated an aliased child import");
}
for (const required of [
  "function mount(target, props)",
  "createText(props[0])",
]) {
  if (!blipSource.includes(required)) {
    throw new Error(`generated Blip is missing ${required}`);
  }
  if (!chipSource.includes(required)) {
    throw new Error(`generated Chip is missing ${required}`);
  }
}
if (blipSource.includes("$lrx_child") || blipSource.includes("Blip.mjs")) {
  throw new Error("generated Blip module unexpectedly nests children");
}
if (chipSource.includes("$lrx_child") || chipSource.includes("Chip.mjs")) {
  throw new Error("generated Chip module unexpectedly nests children");
}

const generated = await import(pathToFileURL(path.join(directory, "NestLab.mjs")).href);
if (typeof generated.mount !== "function") {
  throw new Error("generated Nest Lab does not export mount");
}

console.log("generated Nest Lab artifacts passed");
