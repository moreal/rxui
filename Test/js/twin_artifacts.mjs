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
    "keyed-regions", "typed-row-events", "row-reflects", "row-aggregates",
    "region-filters", "routing",
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
  // ADR-0080: `right` names one literal (`"mixed"`) its twin does not. The
  // two chains stay independent — `left`'s chain has no `"mixed"` test at
  // all, so under that literal `left` falls through to show-all.
  "      const filter_scan_1 = [0];\n      for (const filter_row_1 of regions[1][1]) {\n        setProperty(childAt(regions[1][5], filter_scan_1[0]), \"hidden\", state[1] === \"on\" ? filter_row_1[2] !== \"false\" : state[1] === \"off\" ? filter_row_1[2] !== \"true\" : state[1] === \"mixed\" ? filter_row_1[2] !== \"true\" : false);\n        filter_scan_1[0] += 1;\n      }",
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
  // ADR-0080: `left` and `right` each bind one row event of their own kind —
  // a delegated `click` on `left`'s container and a delegated `change` on
  // `right`'s — so the two dispatches never share a listener; `solo` binds
  // none and emits no dispatch at all.
  "const region_off_0 = listenDelegatedCells(node_24, \"click\", state, context, $lrx_region_0_dispatch, [\"\", \"\", \"remove\"]);",
  "const region_off_1_change = listenDelegatedCells(node_25, \"change\", state, context, $lrx_region_1_dispatch, [\"\", \"\", \"toggle\"]);",
  // ADR-0080, axis one — a route over the *shared* filter field. The sealed
  // literal set is the declared default plus the union of both tables over
  // `mode`, so `#/mixed` is legal on the strength of `right`'s table alone
  // even though `left` is declared first.
  "  const route_hash_0 = readHash();\n  state[1] = route_hash_0 === \"#/\" ? \"all\" : route_hash_0 === \"#/on\" ? \"on\" : route_hash_0 === \"#/off\" ? \"off\" : route_hash_0 === \"#/mixed\" ? \"mixed\" : state[1];",
  "function $lrx_route_0(hostState, context, hash) {\n  if (hash === \"#/\") {\n    return $lrx_route_0_arm_0(context, null);\n  }\n  if (hash === \"#/on\") {\n    return $lrx_route_0_arm_1(context, null);\n  }\n  if (hash === \"#/off\") {\n    return $lrx_route_0_arm_2(context, null);\n  }\n  if (hash === \"#/mixed\") {\n    return $lrx_route_0_arm_3(context, null);\n  }\n  return $lrx_route_0_arm_0(context, null);\n}",
  // One route write per commit, behind the routed field's own changed bit —
  // not per filtered region. Two regions filter on `mode`; there is still
  // exactly one `route:mode:write` block, and it sits ahead of both sweeps.
  "    if (changed[1]) {\n      if (state[1] === \"all\") {\n        writeHash(\"#/\");\n      }\n      if (state[1] === \"on\") {\n        writeHash(\"#/on\");\n      }\n      if (state[1] === \"off\") {\n        writeHash(\"#/off\");\n      }\n      if (state[1] === \"mixed\") {\n        writeHash(\"#/mixed\");\n      }\n      tx[7][\"push\"](\"route:mode:write\");\n    }",
  // ADR-0080, axis two — a pending-row drain beside a filter sweep at region
  // index *1*: the `updateAt` loop settles the retained row and the very
  // next statement is that region's own filter sweep, both woken by the one
  // `region_touched_1` flag the drain's pending array feeds.
  "    if (regions[1][4][\"length\"] !== 0) {\n      for (const pending_row of regions[1][4]) {\n        regions[1][0][\"updateAt\"](pending_row, regions[1][1][pending_row], null);\n        tx[7][\"push\"](\"region:right:updateAt\");\n      }\n      regions[1][4] = [];\n    }\n    if (region_touched_1 || changed[1]) {",
]) {
  if (!twinSource.includes(required)) {
    throw new Error(`generated Twin Lab is missing ${required}`);
  }
}
for (const banned of [
  "$lrx_region_2_dispatch",
  "count_next_1_",
  "count_next_2_",
  "filter_scan_3",
  // ADR-0080: the union rule seals the literal set for *validation* only —
  // it never merges the tables. `left` declares no `"mixed"` arm, so no
  // `filter_row_0` test for it may appear, and no second route item or
  // per-region hash write may either.
  "filter_row_0[2] !== \"true\" : state[1] === \"mixed\"",
  "$lrx_route_1",
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
