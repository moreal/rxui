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
  twinManifest.runtimeAbi !== 18 ||
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
    "region-filters", "routing", "persistence",
  ])
) {
  throw new Error("generated Twin Lab manifest is invalid");
}

const twinSource = await readFile(path.join(directory, "TwinLab.mjs"), "utf8");
// ADR-0087 seals the flush point: a persisted region's storageSet runs inside
// the commit, so the store is current the moment the dispatch returns. The
// deferral primitives a per-task flush would need are banned outright, so the
// emission cannot acquire a flush point behind the contract's back.
for (const banned of [
  "currentObserver", "new Proxy", "eval(", "Function(",
  "queueMicrotask", "setTimeout", "requestAnimationFrame", "Promise",
]) {
  if (twinSource.includes(banned)) {
    throw new Error(`generated Twin Lab contains ${banned}`);
  }
}
for (const required of [
  "import { createKeyedRegion } from \"./leanrx_region.mjs\";",
  // ADR-0079: three filtered regions, and the filter container slot is
  // `5 + counts?2` computed inside the per-region loop — `left` carries a
  // count so its container sits at 7, while `right` and `solo` carry none so
  // the same container rides slot 5. Nothing about the filter feature is
  // component-wide.
  // ADR-0081: `right` is persisted, and this line is the proof that
  // persistence adds no region-record slot — every slot up to the container
  // is byte-for-byte what ADR-0080 pinned.
  // ADR-0097/0098: all three regions remove and append, so each record grows
  // the drops queue and then the append counter, in that order, at its own
  // end — which is why no earlier slot index moved.
  "const regions = [[region_0, [], 0, false, [], [count_text_22, count_text_24], [0, 0], node_26, [], 0, [0]], [region_1, [], 0, false, [], node_27, [], 0], [region_2, [], 0, false, [], node_28, [], 0]];",
  // Each region's wake flag is its own, read before the reconcile consumes
  // the dirty bit and the pending positions.
  "    const region_touched_1 = regions[1][3] || regions[1][6][\"length\"] !== 0 || regions[1][7] !== 0 || regions[1][4][\"length\"] !== 0;",
  "    const region_touched_2 = regions[2][3] || regions[2][6][\"length\"] !== 0 || regions[2][7] !== 0 || regions[2][4][\"length\"] !== 0;",
  // ADR-0083: `left`'s only drain path writes `label`; its filter arms and
  // its predicate count read `flag`, and its row total reads no field at
  // all. Every sweep over the region is therefore disjoint from the drain,
  // so `left` declares *only* the structural flag — the flag set is derived
  // per region from the read sets, not fixed by the feature list.
  "    const region_structural_0 = regions[0][3] || regions[0][8][\"length\"] !== 0 || regions[0][9] !== 0;",
  // ADR-0079, axis one — two filtered regions: two scans with their own
  // `filter_scan_{i}` / `filter_row_{i}` identifiers, each navigating
  // `childAt` from *its own* container slot, so neither walk can reach the
  // other's container or row table. The two inline arm tables are inverted,
  // so one field value hides complementary rows in the two regions.
  "      const filter_read_0 = [0];\n      const filter_written_0 = [0];\n      const filter_at_0 = [0];\n      if (!(filter_dirty_0 || changed[1])) {\n        for (const filter_position_0 of filter_moved_0) {\n          const filter_moved_row_0 = regions[0][1][filter_position_0];\n          const filter_moved_next_0 = state[1] === \"on\" ? filter_moved_row_0[2] !== \"true\" : state[1] === \"off\" ? filter_moved_row_0[2] !== \"false\" : false;\n          if (filter_moved_row_0[3] !== filter_moved_next_0) {\n            filter_moved_row_0[3] = filter_moved_next_0;\n            setProperty(childAt(regions[0][7], filter_position_0), \"hidden\", filter_moved_next_0);\n            filter_written_0[0] += 1;\n          }\n          filter_read_0[0] += 1;\n        }\n        filter_at_0[0] = regions[0][1][\"length\"] - filter_added_0;\n      }\n      while (filter_at_0[0] < regions[0][1][\"length\"]) {\n        const filter_row_0 = regions[0][1][filter_at_0[0]];\n        const filter_next_0 = state[1] === \"on\" ? filter_row_0[2] !== \"true\" : state[1] === \"off\" ? filter_row_0[2] !== \"false\" : false;\n        if (filter_row_0[3] !== filter_next_0) {\n          filter_row_0[3] = filter_next_0;\n          setProperty(childAt(regions[0][7], filter_at_0[0]), \"hidden\", filter_next_0);\n          filter_written_0[0] += 1;\n        }\n        filter_read_0[0] += 1;\n        filter_at_0[0] += 1;\n      }",
  // ADR-0080: `right` names one literal (`"mixed"`) its twin does not. The
  // two chains stay independent — `left`'s chain has no `"mixed"` test at
  // all, so under that literal `left` falls through to show-all.
  "      const filter_read_1 = [0];\n      const filter_written_1 = [0];\n      const filter_at_1 = [0];\n      if (!(filter_dirty_1 || changed[1])) {\n        for (const filter_position_1 of filter_moved_1) {\n          const filter_moved_row_1 = regions[1][1][filter_position_1];\n          const filter_moved_next_1 = state[1] === \"on\" ? filter_moved_row_1[2] !== \"false\" : state[1] === \"off\" ? filter_moved_row_1[2] !== \"true\" : state[1] === \"mixed\" ? filter_moved_row_1[2] !== \"true\" : false;\n          if (filter_moved_row_1[4] !== filter_moved_next_1) {\n            filter_moved_row_1[4] = filter_moved_next_1;\n            setProperty(childAt(regions[1][5], filter_position_1), \"hidden\", filter_moved_next_1);\n            filter_written_1[0] += 1;\n          }\n          filter_read_1[0] += 1;\n        }\n        filter_at_1[0] = regions[1][1][\"length\"] - filter_added_1;\n      }\n      while (filter_at_1[0] < regions[1][1][\"length\"]) {\n        const filter_row_1 = regions[1][1][filter_at_1[0]];\n        const filter_next_1 = state[1] === \"on\" ? filter_row_1[2] !== \"false\" : state[1] === \"off\" ? filter_row_1[2] !== \"true\" : state[1] === \"mixed\" ? filter_row_1[2] !== \"true\" : false;\n        if (filter_row_1[4] !== filter_next_1) {\n          filter_row_1[4] = filter_next_1;\n          setProperty(childAt(regions[1][5], filter_at_1[0]), \"hidden\", filter_next_1);\n          filter_written_1[0] += 1;\n        }\n        filter_read_1[0] += 1;\n        filter_at_1[0] += 1;\n      }",
  "      const filter_read_2 = [0];\n      const filter_written_2 = [0];\n      const filter_at_2 = [0];\n      if (!(filter_dirty_2 || changed[2])) {\n        filter_at_2[0] = regions[2][1][\"length\"] - filter_added_2;\n      }\n      while (filter_at_2[0] < regions[2][1][\"length\"]) {\n        const filter_row_2 = regions[2][1][filter_at_2[0]];\n        const filter_next_2 = state[2] === \"on\" ? filter_row_2[2] !== \"true\" : false;\n        if (filter_row_2[3] !== filter_next_2) {\n          filter_row_2[3] = filter_next_2;\n          setProperty(childAt(regions[2][5], filter_at_2[0]), \"hidden\", filter_next_2);\n          filter_written_2[0] += 1;\n        }\n        filter_read_2[0] += 1;\n        filter_at_2[0] += 1;\n      }\n      tx[7][\"push\"](\"filter:solo:read:\" + filter_read_2[0]);\n      tx[7][\"push\"](\"filter:solo:written:\" + filter_written_2[0]);\n      if (filter_written_2[0] !== 0) {\n        tx[9] += 1;\n        tx[7][\"push\"](\"dom:filter:solo:write\");\n      }\n    }\n    tx[1] += 1;\n    tx[7][\"push\"](\"transaction:commit\");\n  }",
  // ADR-0079, axis two — two filters over one state field: `left` and
  // `right` both wake on `changed[1]`, `solo` only on `changed[2]`. Each
  // guard names exactly one region's flag and exactly one field's bit, and
  // the three blocks sit in region declaration order inside one commit.
  // ADR-0082: `left` wakes on the structural bit, `right` — whose drain
  // writes the very field its arms read — still on the touched flag, and
  // `solo`, which has no drain path at all, keeps the uniform flag because
  // its pending slot is provably empty.
  //
  "    if (region_structural_0 || changed[1]) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"filter:left:evaluated\");",
  "    if (region_touched_1 || changed[1]) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"filter:right:evaluated\");",
  "    if (region_touched_2 || changed[2]) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"filter:solo:evaluated\");",
  // The row-aggregate sweep stays `left`'s alone: one count cell, one
  // region-local slot, and no count code under the unaggregated neighbours.
  "      setText(regions[0][5][0], count_next_0_0);",
  // `stir` mixes the two wake reasons in one transaction — a structural
  // touch of `solo` beside a write to the twins' filter field — so the one
  // commit runs all three sweeps, two woken by the changed bit and one by
  // its own touched flag.
  "  tx[7][\"push\"](\"event:stir\");\n  regions[2][1][\"push\"]([regions[2][2], $lrx_event_8_append_0_0(state[0], state[1], state[2]), $lrx_event_8_append_0_1(state[0], state[1], state[2]), null]);\n  regions[2][2] += 1;\n  regions[2][7] += 1;\n  tx[7][\"push\"](\"region:solo:append\");\n  state[1] = $lrx_event_8_write_1(state[0], state[1], state[2]);",
  // ADR-0080: `left` and `right` each bind one row event of their own kind —
  // a delegated `click` on `left`'s container and a delegated `change` on
  // `right`'s — so the two dispatches never share a listener; `solo` binds
  // none and emits no dispatch at all.
  "const region_off_0 = listenDelegatedCells(node_26, \"click\", state, context, $lrx_region_0_dispatch, [\"\", \"\", \"remove\", \"mark\"]);",
  // ADR-0083: the count sweep beside the narrowed filter sweep reads the
  // same structural bit — the row total reads only `rows.length` and the
  // predicate count reads `flag`, so a `mark` drain (which writes `label`)
  // asks neither. The two counts agree on their flag, so they share one
  // block rather than growing a second guard.
  "    const region_structural_0 = regions[0][3] || regions[0][8][\"length\"] !== 0 || regions[0][9] !== 0;\n    if (regions[0][3]) {\n      regions[0][10][0] = 0;\n      for (const count_row_0 of regions[0][1]) {\n        if (count_row_0[2] === \"true\") {\n          regions[0][10][0] += 1;\n        }\n      }\n      tx[7][\"push\"](\"predicate:left:read:\" + regions[0][1][\"length\"]);\n    }\n    if (region_structural_0) {\n      tx[5] += 1;\n      tx[7][\"push\"](\"count:left:0:evaluated\");",
  "      tx[7][\"push\"](\"count:left:1:evaluated\");\n      const count_next_0_1 = regions[0][10][0];",
  "const region_off_1_change = listenDelegatedCells(node_27, \"change\", state, context, $lrx_region_1_dispatch, [\"\", \"\", \"toggle\"]);",
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
  // ADR-0081 — a routed field driving two regions of which one persists.
  // The two write paths are guarded on different things by construction:
  // the persistence sweep rides `region_touched_1` *alone*, with no
  // `changed[1]` disjunct, so a route flip can never provoke a storageSet.
  "    if (region_touched_1) {\n      const persist_rows_1 = [];",
  // ADR-0085: the serialization cache is a *row tuple* cell, not a record
  // slot, and it exists only where a region is persisted. ADR-0086 puts the
  // displayed-state cell behind it, and all three regions are filtered, so
  // `right` — the one persisted region of three — carries *two* cells behind
  // its two declared fields, serial at 3 and shown at 4, and its row stage
  // stales the first without touching the second...
  "  regions[1][1][\"push\"]([regions[1][2], $lrx_event_0_append_1_0(state[0], state[1], state[2]), $lrx_event_0_append_1_1(state[0], state[1], state[2]), null, null]);",
  "      persist_row_1[3] = persist_row_1[1]",
  "      const row_next_0 = checked ? \"true\" : \"false\";\n      row_item[2] = row_next_0;\n      row_item[3] = null;\n      regions[1][4][\"push\"](scan);",
  // ...while `left` and `solo` carry the displayed-state cell alone, at slot
  // 3, and `left`'s own row stage — which writes `label`, a field no filter
  // arm reads — stales nothing at all. No record slot moved for any of the
  // three.
  "  regions[0][1][\"push\"]([regions[0][2], $lrx_event_0_append_0_0(state[0], state[1], state[2]), $lrx_event_0_append_0_1(state[0], state[1], state[2]), null]);",
  "  regions[2][1][\"push\"]([regions[2][2], $lrx_event_0_append_2_0(state[0], state[1], state[2]), $lrx_event_0_append_2_1(state[0], state[1], state[2]), null]);",
  "      storageSet(\"leanrx-twin-lab.right\", persist_rows_1[\"join\"](\";\"));\n      tx[7][\"push\"](\"storage:right:encode:\" + persist_encoded_1[0]);\n      tx[7][\"push\"](\"storage:right:write\");",
  // ...while the canonical hash write rides `changed[1]` in the commit
  // prologue, ahead of *every* region block — the first region wake flag in
  // the commit is the statement that follows it.
  "      tx[7][\"push\"](\"route:mode:write\");\n    }\n    const filter_dirty_0 = regions[0][3];\n    const filter_moved_0 = regions[0][4];\n    const filter_added_0 = regions[0][9];\n    const region_structural_0 = regions[0][3] || regions[0][8][\"length\"] !== 0 || regions[0][9] !== 0;",
  // Mount seeds the routed field from the hash before the DOM exists and
  // hydrates the persisted region after the listeners are wired, so the
  // hydrate transaction's own sweep applies the routed literal to the rows
  // it just mounted.
  "  const route_off_0 = listenHash(state, context, $lrx_route_0);\n  $lrx_hydrate_0(context, null);",
  "  const stored_value = storageGet(\"leanrx-twin-lab.right\");",
]) {
  if (!twinSource.includes(required)) {
    throw new Error(`generated Twin Lab is missing ${required}`);
  }
}
for (const banned of [
  "$lrx_region_2_dispatch",
  "count_next_1_",
  "count_next_2_",
  "filter_at_3",
  "filter_read_3",
  // ADR-0080: the union rule seals the literal set for *validation* only —
  // it never merges the tables. `left` declares no `"mixed"` arm, so no
  // `filter_row_0` test for it may appear, and no second route item or
  // per-region hash write may either.
  "filter_row_0[2] !== \"true\" : state[1] === \"mixed\"",
  "$lrx_route_1",
  // ADR-0081: one persist item, on `right` alone — the other two regions of
  // the same component emit no serialization at all, and the persistence
  // sweep never acquires the filter sweep's field disjunct.
  "storage:left:write",
  "storage:solo:write",
  "persist_rows_0",
  "persist_rows_2",
  "$lrx_hydrate_1",
  "if (region_touched_1 || changed[1]) {\n      const persist_rows_1",
  // ADR-0082: the narrowing is per region and per sweep. `right`'s drain
  // writes its filter's subject, so its sweep keeps the touched flag; the
  // two regions without a narrowed sweep grow no structural flag at all.
  "const region_structural_1",
  "const region_structural_2",
  "if (region_touched_0 || changed[1]) {",
  // ADR-0083: every sweep over `left` is disjoint from what its drain
  // writes, so the region's touched flag has no reader left and is not
  // bound at all — the flag set follows the read sets, not the features.
  "region_touched_0",
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
