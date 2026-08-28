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
  mixManifest.eventCount !== 8 ||
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
  "const region_0 = createKeyedRegion(node_13, $lrx_region_0_row, $lrx_region_0_update, $lrx_region_0_dispose);",
  "const region_1 = createKeyedRegion(node_27, $lrx_region_1_row, $lrx_region_1_update, $lrx_region_1_dispose);",
  "const child_off_0 = $lrx_child_0(node_0, [\"static badge\"]);",
  // ADR-0076: the child-composing region carrying counts, a filter, and
  // persistence takes the widest record layout — the base five slots, the two
  // ADR-0050 count slots, the ADR-0051 container slot, and the ADR-0075 live
  // children inventory in the last slot, exactly the regionChildSlot formula
  // (5 + counts?2 + filter?1 = 8). ADR-0078: the second child-composing
  // region now carries its own single count and its own persist key but no
  // filter, so its inventory lands at 5 + 2 + 0 = 7 — the slot number that
  // means *container* in crew's record and *inventory* in pins', the sharpest
  // evidence every feature slot is computed per region. Both records still
  // end in the one shared mount-scope array identifier (ADR-0077), and each
  // region's count refs and cache are its own arrays, sized by its own cells.
  "const childInventory = [child_off_0];",
  "const regions = [[region_0, [], 0, false, [], [count_text_10, count_text_12], [0, 0], node_13, childInventory], [region_1, [], 0, false, [], [count_text_25], [0], childInventory]];",
  // The reconcile and drain forward each region's own slot as the child
  // context, so every mount path — appends, broadcasts, and the ADR-0063
  // hydration that rides the same dirty-flag commit — pushes into the shared
  // inventory through a per-region slot number.
  "regions[0][0][\"update\"](regions[0][1], regions[0][8]);",
  "regions[0][0][\"updateAt\"](pending_row, regions[0][1][pending_row], regions[0][8]);",
  "regions[1][0][\"update\"](regions[1][1], regions[1][7]);",
  // ADR-0077: the broadcast writes every retained row's `done` in place and
  // raises the dirty flag — the reconcile retains every key, so it re-renders
  // rows through the update callback and never remounts a row child.
  "  for (const row_item of regions[0][1]) {\n    const row_next_0 = \"true\";\n    row_item[2] = row_next_0;\n  }\n  regions[0][3] = true;\n  tx[7][\"push\"](\"region:crew:broadcast\");",
  // ADR-0051: the filter sweep navigates row roots from the container slot —
  // slot 7 here, behind the count slots — untouched by the inventory slot
  // behind it, and writes `hidden` without ever touching a child. ADR-0078:
  // the scan identifier carries the region index, so the one filtered region
  // owns `filter_scan_0` alone and an unfiltered neighbour emits no scan.
  "setProperty(childAt(regions[0][7], filter_scan_0[0]), \"hidden\", state[1] === \"active\" ? filter_row_0[2] !== \"false\" : state[1] === \"done\" ? filter_row_0[2] !== \"true\" : false);",
  // ADR-0078: the count sweep distributes by region record — crew's two cells
  // fill its own two-slot refs and cache, pins' single cell its own one-slot
  // pair, and the trace labels carry the region name with a region-local
  // slot index.
  "      setText(regions[0][5][1], count_next_0_1);",
  "      setText(regions[1][5][0], count_next_1_0);",
  "      tx[7][\"push\"](\"count:pins:0:evaluated\");",
  // ADR-0059/ADR-0078: region-subject attr selections keep document-order
  // labels across the region boundary — crew owns attrs 0 and 1, pins owns
  // attr 2, and each re-evaluates only under its own region's touched flag.
  "      tx[7][\"push\"](\"attr:2:hidden:evaluated\");\n      const attr_next_2 = regions[1][1][\"length\"] === 0;",
  // ADR-0075: each row mount callback mounts its row-scoped Badge with a
  // never-written projection, stashes it on the row root, and pushes it into
  // the live inventory; each region's dispose callback splices its own row's
  // stashed instance back out by indexOf — a per-row function identity, so
  // neither region can misidentify the other's entries (ADR-0077).
  "const row_child_0 = $lrx_child_0(row_0, [item[3]]);",
  "const row_child_0 = $lrx_child_0(row_0, [item[1]]);",
  "context[\"push\"](row_child_0);",
  "row_0[\"$lrxRowChild\"] = row_child_0;",
  "function $lrx_region_0_dispose(row, key, context) {\n  if (context) {\n    context[\"splice\"](context[\"indexOf\"](row[\"$lrxRowChild\"]), 1);\n  }\n  row[\"$lrxRowChild\"]();\n  return null;\n}",
  "function $lrx_region_1_dispose(row, key, context) {\n  if (context) {\n    context[\"splice\"](context[\"indexOf\"](row[\"$lrxRowChild\"]), 1);\n  }\n  row[\"$lrxRowChild\"]();\n  return null;\n}",
  // ADR-0077: the pins rows are immutable — the retained-row callback is the
  // no-op, so a retained pin touches neither its DOM nor its child.
  "function $lrx_region_1_update(row, item, position, context) {\n  return null;\n}",
  // ADR-0063: hydration is one ordinary mount-time transaction over the
  // shared commit sweep, so hydrated rows mount their Badges through the
  // same context-forwarding reconcile. ADR-0078: two persisted regions mean
  // two hydrate transactions, emitted and run in persist declaration order —
  // each reading its own key, each settling the whole sweep before the next
  // begins — and two write-backs, one per region-touched flag.
  "function $lrx_hydrate_0(context, ignored) {",
  "  const stored_value = storageGet(\"leanrx-mix-lab.crew\");",
  "function $lrx_hydrate_1(context, ignored) {",
  "  const stored_value = storageGet(\"leanrx-mix-lab.pins\");",
  "  $lrx_hydrate_0(context, null);\n  $lrx_hydrate_1(context, null);",
  "storageSet(\"leanrx-mix-lab.crew\", persist_rows_0[\"join\"](\";\"));",
  "storageSet(\"leanrx-mix-lab.pins\", persist_rows_1[\"join\"](\";\"));",
  // ADR-0078: one chained event touches both regions in one transaction — the
  // pins append and the crew removal raise their own dirty flags in *event*
  // order, and the commit sweep then drains them in *region declaration*
  // order, crew before pins.
  "  tx[7][\"push\"](\"event:stowDone\");\n  regions[1][1][\"push\"]([regions[1][2], $lrx_event_4_append_0_0(state[0], state[1])]);\n  regions[1][2] += 1;\n  regions[1][3] = true;\n  tx[7][\"push\"](\"region:pins:append\");",
  "  regions[0][1] = kept_1;\n  regions[0][3] = true;\n  tx[7][\"push\"](\"region:crew:removeIf\");",
  // The Badge cells dispatch no delegated action — no carve-out needed.
  "const region_off_0 = listenDelegatedCells(node_13, \"click\", state, context, $lrx_region_0_dispatch, [\"\", \"\", \"remove\", \"\"]);",
  "const region_off_0_change = listenDelegatedCells(node_13, \"change\", state, context, $lrx_region_0_dispatch, [\"\", \"toggle\", \"\", \"\"]);",
  "const region_off_1 = listenDelegatedCells(node_27, \"click\", state, context, $lrx_region_1_dispatch, [\"\", \"remove\", \"\"]);",
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
