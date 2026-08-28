import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Mix Lab directory");

const mixManifest = JSON.parse(
  await readFile(path.join(directory, "MixLab.mjs.manifest.json"), "utf8"),
);
if (
  mixManifest.compilerVersion !== "0.1.0-dev" ||
  mixManifest.module !== "MixLab.mjs" ||
  typeof mixManifest.graphHash !== "string" ||
  mixManifest.graphHash.length === 0 ||
  mixManifest.runtimeAbi !== 17 ||
  JSON.stringify(mixManifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(mixManifest.stateSlots) !== JSON.stringify(["int", "string"]) ||
  mixManifest.sourceCount !== 2 ||
  mixManifest.derivedCount !== 0 ||
  mixManifest.textSinkCount !== 0 ||
  mixManifest.eventCount !== 5 ||
  JSON.stringify(mixManifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./leanrx_region.mjs", "./Badge.mjs"]) ||
  JSON.stringify(mixManifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "attr-selections", "child-components", "keyed-regions",
    "row-child-components", "typed-row-events", "row-reflects",
    "row-aggregates", "region-broadcasts", "region-filters",
    "region-visibility", "predicate-visibility", "persistence",
  ])
) {
  throw new Error("generated Mix Lab manifest is invalid");
}

const badgeManifest = JSON.parse(
  await readFile(path.join(directory, "Badge.mjs.manifest.json"), "utf8"),
);
if (
  badgeManifest.module !== "Badge.mjs" ||
  JSON.stringify(badgeManifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs"]) ||
  JSON.stringify(badgeManifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "immutable-props",
  ])
) {
  throw new Error("generated Badge manifest is invalid");
}

const mixSource = await readFile(path.join(directory, "MixLab.mjs"), "utf8");
const badgeSource = await readFile(path.join(directory, "Badge.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function("]) {
  if (mixSource.includes(banned) || badgeSource.includes(banned)) {
    throw new Error(`generated Mix Lab contains ${banned}`);
  }
}
for (const required of [
  "import { mount as $lrx_child_0 } from \"./Badge.mjs\";",
  "import { createKeyedRegion } from \"./leanrx_region.mjs\";",
  "const region_0 = createKeyedRegion(node_11, $lrx_region_0_row, $lrx_region_0_update, $lrx_region_0_dispose);",
  "const child_off_0 = $lrx_child_0(node_0, [\"static badge\"]);",
  // ADR-0076: the child-composing region carrying counts, a filter, and
  // persistence takes the widest record layout — the base five slots, the two
  // ADR-0050 count slots, the ADR-0051 container slot, and the ADR-0075 live
  // children inventory in the last slot, exactly the regionChildSlot formula
  // (5 + counts?2 + filter?1 = 8).
  "const childInventory = [child_off_0];",
  "const regions = [[region_0, [], 0, false, [], [count_text_8, count_text_10], [0, 0], node_11, childInventory]];",
  // The reconcile and drain forward the last slot as the child context, so
  // every mount path — appends, broadcasts, and the ADR-0063 hydration that
  // rides the same dirty-flag commit — pushes into the shared inventory.
  "regions[0][0][\"update\"](regions[0][1], regions[0][8]);",
  "regions[0][0][\"updateAt\"](pending_row, regions[0][1][pending_row], regions[0][8]);",
  // ADR-0051: the filter sweep navigates row roots from the container slot —
  // slot 7 here, behind the count slots — untouched by the inventory slot
  // behind it, and writes `hidden` without ever touching a child.
  "setProperty(childAt(regions[0][7], filter_scan_0[0]), \"hidden\", state[1] === \"active\" ? filter_row_0[2] !== \"false\" : state[1] === \"done\" ? filter_row_0[2] !== \"true\" : false);",
  // ADR-0075: each row mount callback mounts its row-scoped Badge with a
  // never-written projection, stashes it on the row root, and pushes it into
  // the live inventory; the region's dispose callback splices its own row's
  // stashed instance back out by indexOf — a per-row function identity.
  "const row_child_0 = $lrx_child_0(row_0, [item[3]]);",
  "context[\"push\"](row_child_0);",
  "row_0[\"$lrxRowChild\"] = row_child_0;",
  "function $lrx_region_0_dispose(row, key, context) {\n  if (context) {\n    context[\"splice\"](context[\"indexOf\"](row[\"$lrxRowChild\"]), 1);\n  }\n  row[\"$lrxRowChild\"]();\n  return null;\n}",
  // ADR-0063: hydration is one ordinary mount-time transaction over the
  // shared commit sweep, so hydrated rows mount their Badges through the
  // same context-forwarding reconcile.
  "function $lrx_hydrate_0(context, ignored) {",
  "  const stored_value = storageGet(\"leanrx-mix-lab.crew\");",
  "  $lrx_hydrate_0(context, null);",
  "storageSet(\"leanrx-mix-lab.crew\", persist_rows_0[\"join\"](\";\"));",
  // The Badge cells dispatch no delegated action — no carve-out needed.
  "const region_off_0 = listenDelegatedCells(node_11, \"click\", state, context, $lrx_region_0_dispatch, [\"\", \"\", \"remove\", \"\"]);",
  "const region_off_0_change = listenDelegatedCells(node_11, \"change\", state, context, $lrx_region_0_dispatch, [\"\", \"toggle\", \"\", \"\"]);",
  "disposer[\"children\"] = childInventory;",
]) {
  if (!mixSource.includes(required)) {
    throw new Error(`generated Mix Lab is missing ${required}`);
  }
}
for (const required of [
  "function mount(target, props)",
  "createText(props[0])",
]) {
  if (!badgeSource.includes(required)) {
    throw new Error(`generated Badge is missing ${required}`);
  }
}
if (badgeSource.includes("$lrx_child") || badgeSource.includes("Badge.mjs")) {
  throw new Error("generated Badge module unexpectedly nests children");
}

const generated = await import(pathToFileURL(path.join(directory, "MixLab.mjs")).href);
if (typeof generated.mount !== "function") {
  throw new Error("generated Mix Lab does not export mount");
}

console.log("generated Mix Lab artifacts passed");
