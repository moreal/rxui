import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Twin Lab directory");

const twinManifest = JSON.parse(
  await readFile(path.join(directory, "TwinLab.mjs.manifest.json"), "utf8"),
);
if (
  twinManifest.compilerVersion !== "0.1.0-dev" ||
  twinManifest.module !== "TwinLab.mjs" ||
  typeof twinManifest.graphHash !== "string" ||
  twinManifest.graphHash.length === 0 ||
  twinManifest.runtimeAbi !== 17 ||
  JSON.stringify(twinManifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(twinManifest.stateSlots) !==
    JSON.stringify(["int", "string", "string"]) ||
  twinManifest.sourceCount !== 3 ||
  twinManifest.derivedCount !== 0 ||
  twinManifest.textSinkCount !== 0 ||
  twinManifest.eventCount !== 9 ||
  JSON.stringify(twinManifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./leanrx_region.mjs"]) ||
  JSON.stringify(twinManifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "keyed-regions", "row-aggregates", "region-filters",
  ])
) {
  throw new Error("generated Twin Lab manifest is invalid");
}

const twinSource = await readFile(path.join(directory, "TwinLab.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function("]) {
  if (twinSource.includes(banned)) {
    throw new Error(`generated Twin Lab contains ${banned}`);
  }
}
for (const required of [
  "import { createKeyedRegion } from \"./leanrx_region.mjs\";",
  // ADR-0079: three filtered regions, and the filter container slot is
  // `5 + counts?2` computed inside the per-region loop — `left` carries a
  // count so its record is eight slots wide with the container at 7, while
  // `right` and `solo` carry none so the same container rides slot 5 of a
  // six-slot record. Nothing about the filter feature is component-wide.
  "const regions = [[region_0, [], 0, false, [], [count_text_22], [0], node_24], [region_1, [], 0, false, [], node_25], [region_2, [], 0, false, [], node_26]];",
  // Each region's touched flag is its own, read before the reconcile
  // consumes the dirty bit and the pending positions.
  "    const region_touched_0 = regions[0][3] || regions[0][4][\"length\"] !== 0;",
  "    const region_touched_1 = regions[1][3] || regions[1][4][\"length\"] !== 0;",
  "    const region_touched_2 = regions[2][3] || regions[2][4][\"length\"] !== 0;",
  // ADR-0079, axis one — two filtered regions: two scans with their own
  // `filter_scan_{i}` / `filter_row_{i}` identifiers, each navigating
  // `childAt` from *its own* container slot, so neither walk can reach the
  // other's container or row table. The two inline arm tables are inverted,
  // so one field value hides complementary rows in the two regions.
  "      const filter_scan_0 = [0];\n      for (const filter_row_0 of regions[0][1]) {\n        setProperty(childAt(regions[0][7], filter_scan_0[0]), \"hidden\", state[1] === \"on\" ? filter_row_0[2] !== \"true\" : state[1] === \"off\" ? filter_row_0[2] !== \"false\" : false);\n        filter_scan_0[0] += 1;\n      }",
  "      const filter_scan_1 = [0];\n      for (const filter_row_1 of regions[1][1]) {\n        setProperty(childAt(regions[1][5], filter_scan_1[0]), \"hidden\", state[1] === \"on\" ? filter_row_1[2] !== \"false\" : state[1] === \"off\" ? filter_row_1[2] !== \"true\" : false);\n        filter_scan_1[0] += 1;\n      }",
  "      const filter_scan_2 = [0];\n      for (const filter_row_2 of regions[2][1]) {\n        setProperty(childAt(regions[2][5], filter_scan_2[0]), \"hidden\", state[2] === \"on\" ? filter_row_2[2] !== \"true\" : false);\n        filter_scan_2[0] += 1;\n      }",
  // ADR-0079, axis two — two filters over one state field: `left` and
  // `right` both wake on `changed[1]`, `solo` only on `changed[2]`. Each
  // guard names exactly one region's flag and exactly one field's bit, and
  // the three blocks sit in region declaration order inside one commit.
  "    if (region_touched_0 || changed[1]) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"filter:left:evaluated\");",
  "    if (region_touched_1 || changed[1]) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"filter:right:evaluated\");",
  "    if (region_touched_2 || changed[2]) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"filter:solo:evaluated\");",
  // The row-aggregate sweep stays `left`'s alone: one count cell, one
  // region-local slot, and no count code under the unaggregated neighbours.
  "      setText(regions[0][5][0], count_next_0_0);",
  // `stir` mixes the two wake reasons in one transaction — a structural
  // touch of `solo` beside a write to the twins' filter field — so the one
  // commit runs all three sweeps, two woken by the changed bit and one by
  // its own touched flag.
  "  tx[7][\"push\"](\"event:stir\");\n  regions[2][1][\"push\"]([regions[2][2], $lrx_event_8_append_0_0(state[0], state[1], state[2]), $lrx_event_8_append_0_1(state[0], state[1], state[2])]);\n  regions[2][2] += 1;\n  regions[2][3] = true;\n  tx[7][\"push\"](\"region:solo:append\");\n  state[1] = $lrx_event_8_write_1(state[0], state[1], state[2]);",
  // Only `left` binds a row event, so only its container carries a
  // delegated listener; the unbound neighbours emit no dispatch at all.
  "const region_off_0 = listenDelegatedCells(node_24, \"click\", state, context, $lrx_region_0_dispatch, [\"\", \"\", \"remove\"]);",
]) {
  if (!twinSource.includes(required)) {
    throw new Error(`generated Twin Lab is missing ${required}`);
  }
}
for (const banned of [
  "$lrx_region_1_dispatch",
  "$lrx_region_2_dispatch",
  "count_next_1_",
  "count_next_2_",
  "filter_scan_3",
]) {
  if (twinSource.includes(banned)) {
    throw new Error(`generated Twin Lab unexpectedly emits ${banned}`);
  }
}

const generated = await import(pathToFileURL(path.join(directory, "TwinLab.mjs")).href);
if (typeof generated.mount !== "function") {
  throw new Error("generated Twin Lab does not export mount");
}

console.log("generated Twin Lab artifacts passed");
