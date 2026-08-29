import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Toggle Lab directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "ToggleLab.mjs.manifest.json"), "utf8"),
);
if (
  manifest.compilerVersion !== "0.1.0-dev" ||
  manifest.module !== "ToggleLab.mjs" ||
  typeof manifest.graphHash !== "string" ||
  manifest.graphHash.length === 0 ||
  // The ADR-0063 execution round is the one ABI 17 bump: five sealed DOM-host
  // exports (readHash, listenHash, writeHash, storageGet, storageSet) for the
  // routing and persistence vocabularies.
  manifest.runtimeAbi !== 17 ||
  JSON.stringify(manifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(manifest.stateSlots) !== JSON.stringify(["int", "string", "string"]) ||
  manifest.sourceCount !== 3 ||
  manifest.derivedCount !== 0 ||
  manifest.textSinkCount !== 1 ||
  manifest.eventCount !== 10 ||
  JSON.stringify(manifest.hostImports) !== JSON.stringify([
    "./leanrx_dom.mjs", "./leanrx_form_events.mjs", "./leanrx_region.mjs",
  ]) ||
  JSON.stringify(manifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "typed-events", "event-guards", "event-key-branches", "controlled-props",
    "attr-selections", "keyed-regions",
    "typed-row-events", "row-key-branches", "row-guards", "row-trim",
    "row-branches", "row-reflects", "row-focus", "row-aggregates",
    "count-labels", "region-broadcasts", "payload-broadcasts", "region-filters",
    "region-visibility", "predicate-visibility", "region-checked",
    "routing", "persistence",
  ])
) {
  throw new Error("generated Toggle Lab manifest is invalid");
}

const source = await readFile(path.join(directory, "ToggleLab.mjs"), "utf8");
// ADR-0087 seals the flush point: a persisted region's storageSet runs inside
// the commit, so the store is current the moment the dispatch returns. The
// deferral primitives a per-task flush would need are banned outright, so the
// emission cannot acquire a flush point behind the contract's back.
for (const banned of [
  "currentObserver", "new Proxy", "eval(", "Function(",
  "queueMicrotask", "setTimeout", "requestAnimationFrame", "Promise",
]) {
  if (source.includes(banned)) {
    throw new Error(`generated Toggle Lab contains ${banned}`);
  }
}
for (const required of [
  // The ADR-0063 routing/persistence vocabularies add the five ABI 17 host
  // exports to the DOM import line, reachability-gated: a component with no
  // route/persist item never names them and emits a byte-identical module.
  "import { createElement, createText, setAttribute, append, listen, setText, makeDisposer, setProperty, setKey, childAt, listenDelegatedCells, focus, readHash, listenHash, writeHash, storageGet, storageSet } from \"./leanrx_dom.mjs\";",
  "import { listenValue, listenKey, listenChecked } from \"./leanrx_form_events.mjs\";",
  "import { createKeyedRegion, detach } from \"./leanrx_region.mjs\";",
  // The ADR-0055 controlled new-todo input rides the ADR-0038 path: the
  // per-keystroke typed event through the existing listenValue export. The
  // ADR-0056 key-branched confirmAdd binds beside it through the existing
  // listenKey export — same input, same host, no ABI bump.
  "  const off_0 = listenValue(node_3, \"input\", state, context, $lrx_typed_event_0);",
  "  const off_1 = listenKey(node_3, \"keydown\", state, context, $lrx_key_event_0);",
  // The ADR-0056 dispatch function: one sealed key equality per arm over the
  // delegated key payload — a non-matching key returns before the context is
  // even destructured. The matched Enter arm is the ADR-0055 guarded
  // transaction function tracing its own event:confirmAdd:Enter label; the
  // Escape arm is unguarded, so its transaction function commits the draft
  // reset unconditionally — the sealed Enter/Escape component set executed
  // on both keys.
  "function $lrx_key_event_0(hostState, context, pressed) {\n  if (pressed === \"Enter\") {\n    return $lrx_key_event_0_arm_0(context, null);\n  }\n  if (pressed === \"Escape\") {\n    return $lrx_key_event_0_arm_1(context, null);\n  }\n  return null;\n}",
  "function $lrx_key_event_0_arm_0(context, ignored) {",
  "  tx[7][\"push\"](\"event:confirmAdd:Enter\");",
  "function $lrx_key_event_0_arm_1(context, ignored) {",
  "  tx[7][\"push\"](\"event:confirmAdd:Escape\");",
  // The Escape arm's write evaluator lives in the pseudo event namespace
  // behind the Enter arm's (events.size + arm index, ADR-0056): the empty
  // string literal written to the component draft, nothing else.
  "  state[2] = $lrx_event_8_write_0(state[0], state[1], state[2]);",
  "function $lrx_event_8_write_0(added, filter, draft) {\n  return \"\";\n}",
  // The Enter arm's guard miss appends through its own evaluator namespace
  // behind the plain events (pseudo event index 7), with the same trimmed
  // append and draft reset the Add button's $lrx_event_1 runs.
  "  regions[0][1][\"push\"]([regions[0][2], $lrx_event_7_append_0_0(state[0], state[1], state[2]), $lrx_event_7_append_0_1(state[0], state[1], state[2]), $lrx_event_7_append_0_2(state[0], state[1], state[2]), $lrx_event_7_append_0_3(state[0], state[1], state[2]), null, null]);",
  "function $lrx_event_7_append_0_0(added, filter, draft) {\n  return draft[\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\");\n}",
  "function $lrx_event_7_write_1(added, filter, draft) {\n  return \"\";\n}",
  // The ADR-0055 sealed skip guard: the guarded add dispatch returns before
  // the transaction begins on a whitespace-only draft — no begin
  // bookkeeping, no event trace, no write, no append, no region touch. The
  // subject is the ASCII-trimmed component draft, riding the ADR-0054
  // asciiTrimPattern emission inline.
  "function $lrx_event_1(context, ignored) {",
  "  if (state[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\") === \"\") {\n    return null;\n  }\n  if (tx[0] === 0) {",
  // The guard miss appends one row with the trimmed label mirrored into the
  // row draft, then resets the component draft — one transaction.
  "  regions[0][1][\"push\"]([regions[0][2], $lrx_event_1_append_0_0(state[0], state[1], state[2]), $lrx_event_1_append_0_1(state[0], state[1], state[2]), $lrx_event_1_append_0_2(state[0], state[1], state[2]), $lrx_event_1_append_0_3(state[0], state[1], state[2]), null, null]);",
  "function $lrx_event_1_append_0_0(added, filter, draft) {\n  return draft[\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\");\n}",
  "function $lrx_event_1_write_1(added, filter, draft) {\n  return \"\";\n}",
  // The ADR-0057 trimmed disabled selection: the Add button mounts with the
  // trimmed-draft equality reflected into its disabled property — the exact
  // equality the ADR-0055 skip guard evaluates — and the commit sweep
  // re-evaluates it behind the draft's changed flag with the shared
  // evaluate-compare-write shape and the tx[8]/tx[9] counters. The ADR-0058
  // empty-region visibility rides the same attr slots: the items list
  // wrapper (node_14, also the region container) mounts hidden — regions
  // mount empty by construction, so the initial cache value is the literal
  // true — through the same setProperty export. The ADR-0059 predicate
  // hidden selection sits between them: the Clear completed button
  // (node_10) mounts hidden through the same slots and the same literal
  // true — an empty region satisfies no predicate. The ADR-0060 toggle-all
  // checked selection (node_15) follows: the box mounts vacuously
  // checked — the same literal true read the other way, no row fails the
  // predicate — through the same setProperty export. The empty-list chrome
  // round reuses the ADR-0058 emptiness subject on two more slots without
  // any grammar change: the toggle-all box carries hidden beside its
  // checked selection (two selections of different attributes share one
  // element — node_15 holds attr slots 3 and 4 — because the ADR-0045
  // duplicate detection keys on the attribute name), and the footer
  // (node_16) wrapping the items-left line and the filter buttons closes
  // the block with the same subject. All three emptiness slots mount the
  // literal true.
  "  const attrRefs = [node_4, node_10, node_14, node_15, node_15, node_16, node_29];",
  "  const attrCache = [state[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\") === \"\", true, true, true, true, true, true];",
  "  setProperty(attrRefs[0], \"disabled\", attrCache[0]);",
  "  setProperty(attrRefs[1], \"hidden\", attrCache[1]);",
  "  setProperty(attrRefs[2], \"hidden\", attrCache[2]);",
  "  setProperty(attrRefs[3], \"checked\", attrCache[3]);",
  "  setProperty(attrRefs[4], \"hidden\", attrCache[4]);",
  "  setProperty(attrRefs[5], \"hidden\", attrCache[5]);",
  // The ADR-0058/0059/0060 sweep re-evaluates every region-count subject
  // before the reconcile consumes the flags, and writes each boolean
  // property only on a flip: the button's subject is the ADR-0050 predicate
  // scan against zero, the wrapper's the row-table emptiness, and the
  // toggle-all box's the not-done predicate scan exported into the checked
  // property with the same attr:{index} label shape. ADR-0083 splits the
  // one block into four by read set: the two `done` predicate subjects
  // (attr 1, attr 3) ride the touched flag because a row drain writes
  // `done`, while the three emptiness subjects read only the row array's
  // length and ride the structural bit — attr 4 and attr 5 are adjacent and
  // agree, so they share one block. The first append still reveals wrapper,
  // toggle-all, and footer in one commit and draining the region re-hides
  // all three in one commit; a row edit no longer re-asks any of them.
  "    if (region_touched_0) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"attr:1:hidden:evaluated\");\n      const attr_next_1 = share_scan_0_1[0] === 0;\n      const attr_changed_1 = attrCache[1] !== attr_next_1;\n      if (attr_changed_1) {\n        attrCache[1] = attr_next_1;\n        setProperty(attrRefs[1], \"hidden\", attr_next_1);\n        tx[9] += 1;\n        tx[7][\"push\"](\"dom:attr:1:hidden:write\");\n      }\n    }\n    if (region_structural_0) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"attr:2:hidden:evaluated\");\n      const attr_next_2 = regions[0][1][\"length\"] === 0;\n      const attr_changed_2 = attrCache[2] !== attr_next_2;\n      if (attr_changed_2) {\n        attrCache[2] = attr_next_2;\n        setProperty(attrRefs[2], \"hidden\", attr_next_2);\n        tx[9] += 1;\n        tx[7][\"push\"](\"dom:attr:2:hidden:write\");\n      }\n    }\n    if (region_touched_0) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"attr:3:checked:evaluated\");\n      const attr_next_3 = share_scan_0_0[0] === 0;\n      const attr_changed_3 = attrCache[3] !== attr_next_3;\n      if (attr_changed_3) {\n        attrCache[3] = attr_next_3;\n        setProperty(attrRefs[3], \"checked\", attr_next_3);\n        tx[9] += 1;\n        tx[7][\"push\"](\"dom:attr:3:checked:write\");\n      }\n    }\n    if (region_structural_0) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"attr:4:hidden:evaluated\");\n      const attr_next_4 = regions[0][1][\"length\"] === 0;\n      const attr_changed_4 = attrCache[4] !== attr_next_4;\n      if (attr_changed_4) {\n        attrCache[4] = attr_next_4;\n        setProperty(attrRefs[4], \"hidden\", attr_next_4);\n        tx[9] += 1;\n        tx[7][\"push\"](\"dom:attr:4:hidden:write\");\n      }\n      tx[8] += 1;\n      tx[7][\"push\"](\"attr:5:hidden:evaluated\");\n      const attr_next_5 = regions[0][1][\"length\"] === 0;\n      const attr_changed_5 = attrCache[5] !== attr_next_5;\n      if (attr_changed_5) {\n        attrCache[5] = attr_next_5;\n        setProperty(attrRefs[5], \"hidden\", attr_next_5);\n        tx[9] += 1;\n        tx[7][\"push\"](\"dom:attr:5:hidden:write\");\n      }\n    }",
  "    if (changed[2]) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"attr:0:disabled:evaluated\");\n      const attr_next_0 = state[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\") === \"\";\n      const attr_changed_0 = attrCache[0] !== attr_next_0;\n      if (attr_changed_0) {\n        attrCache[0] = attr_next_0;\n        setProperty(attrRefs[0], \"disabled\", attr_next_0);\n        tx[9] += 1;\n        tx[7][\"push\"](\"dom:attr:0:disabled:write\");\n      }\n    }",
  // The attr slots ride behind the prop slots; the region record follows
  // them (ADR-0045), so the context carries eleven slots.
  "  const context = [state, refs, tx, oldSources, changed, sinkCache, propRefs, propCache, attrRefs, attrCache, regions];",
  // One structural delegated listener per bound kind, in registration order,
  // each with its own static per-cell action array (ADR-0041/0046/0049).
  "const region_off_0 = listenDelegatedCells(node_14, \"click\", state, context, $lrx_region_0_dispatch, [\"\", \"\", \"commit\", \"remove\"]);",
  "const region_off_0_dblclick = listenDelegatedCells(node_14, \"dblclick\", state, context, $lrx_region_0_dispatch, [\"\", \"edit\", \"\", \"\"]);",
  "const region_off_0_input = listenDelegatedCells(node_14, \"input\", state, context, $lrx_region_0_dispatch, [\"\", \"retype\", \"\", \"\"]);",
  "const region_off_0_keydown = listenDelegatedCells(node_14, \"keydown\", state, context, $lrx_region_0_dispatch, [\"\", \"keys\", \"\", \"\"]);",
  "const region_off_0_change = listenDelegatedCells(node_14, \"change\", state, context, $lrx_region_0_dispatch, [\"toggle\", \"\", \"\", \"\"]);",
  // The ADR-0052 key-branched selection: one eventKey equality per arm
  // inside the existing action match — a matched key runs the ADR-0043
  // scan-evaluate-assign-queue sequence, a non-matching key falls through
  // to the shared commit with no scan, no write, and no trace.
  "  if (action === \"keys\") {\n    if (eventKey === \"Enter\") {",
  // The ADR-0053 remove-if guard on the Enter arm, with the ADR-0054 trim
  // contract: the guard equality and the committed label both evaluate the
  // ASCII-trimmed draft against the row the key search resolved; the miss
  // commits the trimmed assignment sequence.
  // ADR-0092: a guard hit already stands on a resolved position, so it
  // splices at `scan[1]` unconditionally — no second search, and no rebuild.
  "      if (scan !== -1) {\n        const row_item = regions[0][1][scan];\n        const row_guard = row_item[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\") === \"\";\n        if (row_guard) {\n          regions[0][1][\"splice\"](scan, 1);\n          const drop_queued = regions[0][4][\"length\"] === 0;\n          if (drop_queued) {\n            regions[0][8][\"push\"]([scan, key]);\n          }\n          if (!drop_queued) {\n            regions[0][3] = true;\n          }\n          tx[7][\"push\"](\"region:items:keys\");\n        }\n        if (!row_guard) {\n          const row_next_0 = row_item[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\");\n          const row_next_1 = row_item[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\");\n          const row_next_2 = \"view\";\n          row_item[1] = row_next_0;\n          row_item[2] = row_next_1;\n          row_item[4] = row_next_2;\n          row_item[5] = null;\n          regions[0][4][\"push\"](scan);\n          tx[7][\"push\"](\"region:items:keys\");\n        }\n      }\n    }\n    if (eventKey === \"Escape\") {",
  "        const row_next_0 = row_item[1];\n        const row_next_1 = \"view\";\n        row_item[2] = row_next_0;",
  // The ADR-0053 guarded commit with the ADR-0054 trim contract: the OK
  // button's action branch carries the same trimmed guard equality, trimmed
  // label commit, and removal sequence — destroy-on-whitespace-commit
  // through both commit paths, with the Escape revert arm unguarded and
  // untrimmed.
  "      const row_guard = row_item[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\") === \"\";\n      if (row_guard) {\n        regions[0][1][\"splice\"](scan, 1);\n        const drop_queued = regions[0][4][\"length\"] === 0;\n        if (drop_queued) {\n          regions[0][8][\"push\"]([scan, key]);\n        }\n        if (!drop_queued) {\n          regions[0][3] = true;\n        }\n        tx[7][\"push\"](\"region:items:commit\");\n      }\n      if (!row_guard) {\n        const row_next_0 = row_item[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\");\n        const row_next_1 = row_item[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\");\n        const row_next_2 = \"view\";\n        row_item[1] = row_next_0;\n        row_item[2] = row_next_1;\n        row_item[4] = row_next_2;\n        row_item[5] = null;\n        regions[0][4][\"push\"](scan);\n        tx[7][\"push\"](\"region:items:commit\");\n      }",
  // ADR-0092: the key search is one module-level helper, shared by every
  // region and every branch, and `scan` is the position it returns. The loop
  // is the one `while` the emitter models: the window is half-open, the
  // midpoint is floored with `(span - span % 2) / 2` so the arithmetic is
  // exact at every array length, and a match closes the window by assigning
  // `high` into `low`. No region record slot holds an index and no site
  // maintains one — the row table is key-ordered by construction.
  "function $lrx_row_seek(rows, key) {\n  const seek = [0, -1, rows[\"length\"]];\n  while (seek[0] < seek[2]) {\n    const seek_span = seek[0] + seek[2];\n    const seek_mid = (seek_span - seek_span % 2) / 2;\n    const seek_key = rows[seek_mid][0];\n    if (seek_key === key) {\n      seek[1] = seek_mid;\n      seek[0] = seek[2];\n    }\n    if (seek_key < key) {\n      seek[0] = seek_mid + 1;\n    }\n    if (key < seek_key) {\n      seek[2] = seek_mid;\n    }\n  }\n  return seek[1];\n}",
  // The toggle branch entire: the found guard, the row binding, the field
  // write, the ADR-0085 stale and the ADR-0043 queued position are all
  // unmoved — only the resolution of `scan` changed, from an O(N) walk to
  // one O(log N) call.
  "  if (action === \"toggle\") {\n    const scan = $lrx_row_seek(regions[0][1], key);\n    if (scan !== -1) {\n      const row_item = regions[0][1][scan];\n      const row_next_0 = checked ? \"true\" : \"false\";\n      row_item[3] = row_next_0;\n      row_item[5] = null;\n      regions[0][4][\"push\"](scan);\n      tx[7][\"push\"](\"region:items:toggle\");\n    }",
  // The delegated checked boolean lowers to the "true"/"false" string
  // payload inside the toggle action branch (ADR-0049).
  "      const row_next_0 = checked ? \"true\" : \"false\";",
  // The sealed row checked reflection (ADR-0049): the checkbox mounts with
  // its done state and the retained-row update sweep re-writes it.
  "  setProperty(row_2, \"checked\", item[3] === \"true\");",
  "  setProperty(childAt(childAt(row, 0), 0), \"checked\", item[3] === \"true\");",
  // The dblclick edit entry replaces the branch and focuses the editor
  // (ADR-0047/0048): replacement arm only.
  "    detach(childAt(branch_cell_0, 0));",
  "    if (!branch_want_0) {\n      focus(childAt(branch_cell_0, 0));\n    }",
  // The ADR-0061 toggle-all rebinding: the box's change listener is the
  // existing listenChecked form-event export handing the delegated checked
  // boolean to the payload broadcast dispatch — the ADR-0060 payload-less
  // listen mount is replaced, and still no new host export.
  "  const off_6 = listenChecked(node_15, \"change\", state, context, $lrx_typed_event_1);",
  // The ADR-0061 payload broadcast body: the Bool payload lowers to the
  // "true"/"false" strings exactly as the ADR-0049 row payload does, and
  // the write body is the shared ADR-0050 broadcast's — every row's done
  // field from the same evaluate-then-assign loop, then the dirty flag and
  // the same region trace.
  "function $lrx_typed_event_1(hostState, context, checked) {",
  "  tx[7][\"push\"](\"event:toggleAll\");\n  for (const row_item of regions[0][1]) {\n    const row_next_0 = checked ? \"true\" : \"false\";\n    row_item[3] = row_next_0;\n    row_item[5] = null;\n  }\n  regions[0][3] = true;\n  tx[7][\"push\"](\"region:items:broadcast\");",
  // The listenHash removal closure is the first listener whose lifetime is
  // not rooted in the mounted subtree, so it joins the listenerDisposers
  // array explicitly (ADR-0063).
  "makeDisposer(node_0, [off_0, off_1, off_2, off_3, off_4, off_5, off_6, off_7, off_8, off_9, region_off_0, region_off_0_dblclick, region_off_0_input, region_off_0_keydown, region_off_0_change, route_off_0, region_0[\"dispose\"]], tx, [region_0])",
  // The ADR-0063 route seed: mount reads the hash once and folds it through
  // the sealed table into the filter slot before the derived initials and
  // the DOM mount run; an unknown or empty hash keeps the declared default.
  "  const route_hash_0 = readHash();\n  state[1] = route_hash_0 === \"#/\" ? \"all\" : route_hash_0 === \"#/active\" ? \"active\" : route_hash_0 === \"#/completed\" ? \"completed\" : state[1];",
  // The ADR-0063 route dispatch: one sealed hash equality per arm handing
  // the matched set-field transaction the context; an unknown or empty hash
  // falls to the arm carrying the declared default literal.
  "function $lrx_route_0(hostState, context, hash) {\n  if (hash === \"#/\") {\n    return $lrx_route_0_arm_0(context, null);\n  }\n  if (hash === \"#/active\") {\n    return $lrx_route_0_arm_1(context, null);\n  }\n  if (hash === \"#/completed\") {\n    return $lrx_route_0_arm_2(context, null);\n  }\n  return $lrx_route_0_arm_0(context, null);\n}",
  "function $lrx_route_0_arm_1(context, ignored) {",
  "  tx[7][\"push\"](\"event:route:filter:active\");",
  "const route_off_0 = listenHash(state, context, $lrx_route_0);",
  // The ADR-0063 flip-only writeHash ride: the commit sweep writes the
  // canonical hash literal only when the routed field flipped this commit —
  // an equal-value transaction writes nothing, and the WHATWG equal-value
  // hash assignment fires no hashchange, so no echo loop exists.
  "    if (changed[1]) {\n      if (state[1] === \"all\") {\n        writeHash(\"#/\");\n      }\n      if (state[1] === \"active\") {\n        writeHash(\"#/active\");\n      }\n      if (state[1] === \"completed\") {\n        writeHash(\"#/completed\");\n      }\n      tx[7][\"push\"](\"route:filter:write\");\n    }",
  // The ADR-0063 persistence sweep: one storageSet per region-touching
  // transaction on the shared touched flag, serializing the whole row table
  // with the throw-free split/join escape — fields behind the key slot
  // joined by "," and rows by ";".
  // ADR-0085: each row's serialization is cached on the row itself, in the
  // one cell behind the four declared fields — slot 5 for this region — so
  // the sweep encodes exactly the rows a write staled, reads the rest back,
  // and reports the number it encoded as one trace entry. The write-back's
  // own flag stays `region_touched_0`: it reads every field, so no wake rule
  // can narrow it (ADR-0083).
  "    if (region_touched_0) {\n      const persist_rows_0 = [];\n      const persist_encoded_0 = [0];\n      for (const persist_row_0 of regions[0][1]) {\n        if (persist_row_0[5] === null) {\n          persist_row_0[5] = persist_row_0[1][\"split\"](\"%\")[\"join\"](\"%25\")[\"split\"](\",\")[\"join\"](\"%2C\")[\"split\"](\";\")[\"join\"](\"%3B\") + \",\" + persist_row_0[2][\"split\"](\"%\")[\"join\"](\"%25\")[\"split\"](\",\")[\"join\"](\"%2C\")[\"split\"](\";\")[\"join\"](\"%3B\") + \",\" + persist_row_0[3][\"split\"](\"%\")[\"join\"](\"%25\")[\"split\"](\",\")[\"join\"](\"%2C\")[\"split\"](\";\")[\"join\"](\"%3B\") + \",\" + persist_row_0[4][\"split\"](\"%\")[\"join\"](\"%25\")[\"split\"](\",\")[\"join\"](\"%2C\")[\"split\"](\";\")[\"join\"](\"%3B\");\n          persist_encoded_0[0] += 1;\n        }\n        persist_rows_0[\"push\"](persist_row_0[5]);\n      }\n      storageSet(\"leanrx-toggle-lab.items\", persist_rows_0[\"join\"](\";\"));\n      tx[7][\"push\"](\"storage:items:encode:\" + persist_encoded_0[0]);\n      tx[7][\"push\"](\"storage:items:write\");\n    }",
  // ADR-0085: the invalidation is total because the cache is keyed on row
  // *identity*. The two paths that write a field stale the cell they wrote —
  // the ADR-0043 row stage, once per drained row...
  "      row_item[3] = row_next_0;\n      row_item[5] = null;\n      regions[0][4][\"push\"](scan);",
  // ...and the ADR-0050/0061 broadcast, once per row, the only O(N)
  // invalidation in the emission.
  "  for (const row_item of regions[0][1]) {\n    const row_next_0 = \"true\";\n    row_item[3] = row_next_0;\n    row_item[5] = null;\n  }",
  // A fresh row is born unencoded, so the tuple shape never changes after
  // construction and the next write-back fills the cell.
  "$lrx_event_1_append_0_3(state[0], state[1], state[2]), null, null]);",
  // A removal writes no field, so every survivor's serialization cell stays
  // valid — no stale, and nothing re-encodes. ADR-0092 replaced the
  // kept-filter rebuild with a key search and a `splice` at the resolved
  // position: the same survivors, in the same order, without the O(N) walk.
  // ADR-0097 keeps that position instead of throwing it away: it is queued
  // for the commit sweep's `removeAt` drain, and the dirty bit — which would
  // have re-rendered every survivor — is now only the fallback for a
  // transaction that already queued an `updateAt` position the splice would
  // have shifted. The `-1` branch is unreachable from a mounted row's own
  // button and is emitted anyway; an absent key now changes nothing at all
  // but the trace, because there is no position to queue.
  "    const drop = $lrx_row_seek(regions[0][1], key);\n    if (drop !== -1) {\n      regions[0][1][\"splice\"](drop, 1);\n      const drop_queued = regions[0][4][\"length\"] === 0;\n      if (drop_queued) {\n        regions[0][8][\"push\"]([drop, key]);\n      }\n      if (!drop_queued) {\n        regions[0][3] = true;\n      }\n    }\n    tx[7][\"push\"](\"region:items:remove\");",
  // The ADR-0097 drain, ahead of the reconcile and ahead of the ADR-0051
  // filter sweep that navigates by row-table position: one `removeAt` per
  // queued pair, in the order the table was spliced, and the queue is
  // emptied. Every survivor keeps its DOM node and its generated row-update
  // callback goes unrun.
  "    if (regions[0][8][\"length\"] !== 0) {\n      for (const dropped_row of regions[0][8]) {\n        regions[0][0][\"removeAt\"](dropped_row[0], dropped_row[1], null);\n        tx[7][\"push\"](\"region:items:removeAt\");\n      }\n      regions[0][8] = [];\n    }\n    if (regions[0][3]) {\n      regions[0][3] = false;\n      regions[0][0][\"update\"](regions[0][1], null);",
  // The ADR-0063 mount hydration: one ordinary transaction whose writes
  // parse the stored value — arity mismatch fails the whole value closed to
  // the empty region — and push the parsed rows through the existing append
  // path, so the shared commit sweep reconciles rows, counts, visibility,
  // and the filter table together.
  "function $lrx_hydrate_0(context, ignored) {",
  "  tx[7][\"push\"](\"event:hydrate:items\");",
  "  const stored_value = storageGet(\"leanrx-toggle-lab.items\");",
  "        const hydrate_fields = hydrate_part[\"split\"](\",\");\n        if (hydrate_fields[\"length\"] !== 4) {\n          hydrate_ok[0] = false;\n        }\n        hydrate_rows[\"push\"](hydrate_fields);",
  "  if (hydrate_ok[0] && hydrate_rows[\"length\"] !== 0) {\n    for (const hydrate_row of hydrate_rows) {\n      regions[0][1][\"push\"]([regions[0][2], hydrate_row[0][\"split\"](\"%2C\")[\"join\"](\",\")[\"split\"](\"%3B\")[\"join\"](\";\")[\"split\"](\"%25\")[\"join\"](\"%\"), hydrate_row[1][\"split\"](\"%2C\")[\"join\"](\",\")[\"split\"](\"%3B\")[\"join\"](\";\")[\"split\"](\"%25\")[\"join\"](\"%\"), hydrate_row[2][\"split\"](\"%2C\")[\"join\"](\",\")[\"split\"](\"%3B\")[\"join\"](\";\")[\"split\"](\"%25\")[\"join\"](\"%\"), hydrate_row[3][\"split\"](\"%2C\")[\"join\"](\",\")[\"split\"](\"%3B\")[\"join\"](\";\")[\"split\"](\"%25\")[\"join\"](\"%\"), null, null]);\n      regions[0][2] += 1;\n    }\n    regions[0][3] = true;\n    tx[7][\"push\"](\"region:items:hydrate\");\n  }",
  "  $lrx_hydrate_0(context, null);",
  // The ADR-0050 region record carries the count refs and numeric cache in
  // two region-local slots behind the pending slot, and the ADR-0051 filter
  // slot holds the container element behind them. The ADR-0097 drops queue
  // is last, so adding it moved none of the slots those ADRs sealed.
  // The ADR-0062 label count joins the count slots: its ref sits between
  // the predicate count and the total in view order, and its cache slot
  // mounts as the else string — the mounted DOM text of the empty region.
  "const regions = [[region_0, [], 0, false, [], [count_text_19, count_text_20, count_text_22], [0, \" items left\", 0], node_14, []]];",
  // The broadcast writes every row from the sealed row expression and raises
  // the dirty flag; the predicate removal keeps the non-matching rows.
  "  for (const row_item of regions[0][1]) {\n    const row_next_0 = \"true\";\n    row_item[3] = row_next_0;\n    row_item[5] = null;\n  }\n  regions[0][3] = true;",
  "  const kept_0 = [];",
  "  regions[0][1] = kept_0;",
  // The count sweep reads its wake flag before the reconcile consumes it,
  // recomputes each count form, and writes through setText. The ADR-0062
  // label count rides the predicate block: the recomputed predicate count
  // selects one of the two static strings against the one literal, and the
  // selected string takes the cache compare and the setText write. ADR-0083
  // splits the block by read set — both `done` predicate counts keep the
  // touched flag, the row total moves behind the structural bit — so the
  // region declares both flags.
  "    const region_touched_0 = regions[0][3] || regions[0][8][\"length\"] !== 0 || regions[0][4][\"length\"] !== 0;",
  "    const region_structural_0 = regions[0][3] || regions[0][8][\"length\"] !== 0;",
  "    if (region_structural_0) {\n      tx[5] += 1;\n      tx[7][\"push\"](\"count:items:2:evaluated\");\n      const count_next_0_2 = regions[0][1][\"length\"];",
  "        setText(regions[0][5][0], count_next_0_0);",
  "      const count_label_0_1 = count_next_0_1 === 1 ? \" item left\" : \" items left\";",
  "      const count_changed_0_1 = regions[0][6][1] !== count_label_0_1;",
  "        setText(regions[0][5][1], count_label_0_1);",
  // The label mounts as the else string: an empty region counts zero and
  // zero differs from one — the plural branch is the mount text.
  "  const count_text_20 = createText(\" items left\");",
  // The ADR-0051 filter sweep runs after the reconcile and drain whenever
  // the region was touched or the filter field changed, selecting each row
  // from the sealed state-to-predicate table — the unmatched "all" falls
  // through to false.
  "    if (region_touched_0 || changed[1]) {",
  "      tx[7][\"push\"](\"filter:items:evaluated\");",
  // ADR-0086: the selection is compared against the row's own displayed-state
  // cell at slot 6 — behind the four declared fields and the ADR-0085
  // serialization cell at slot 5 — and only a row whose value moved is
  // navigated to by childAt and written. The written count rides one
  // commit-time trace entry, and the shared DOM-write counter takes the
  // ADR-0045 evaluate-compare-write shape: it fires only when a row moved.
  "      const filter_scan_0 = [0];\n      const filter_written_0 = [0];\n      for (const filter_row_0 of regions[0][1]) {\n        const filter_next_0 = state[1] === \"active\" ? filter_row_0[3] !== \"false\" : state[1] === \"completed\" ? filter_row_0[3] !== \"true\" : false;\n        if (filter_row_0[6] !== filter_next_0) {\n          filter_row_0[6] = filter_next_0;\n          setProperty(childAt(regions[0][7], filter_scan_0[0]), \"hidden\", filter_next_0);\n          filter_written_0[0] += 1;\n        }\n        filter_scan_0[0] += 1;\n      }",
  "      tx[7][\"push\"](\"filter:items:written:\" + filter_written_0[0]);\n      if (filter_written_0[0] !== 0) {\n        tx[9] += 1;\n        tx[7][\"push\"](\"dom:filter:items:write\");\n      }",
  // ADR-0084 splits the drain wake by row event inside the region's own
  // dispatch function, which is the only transaction function that can tell
  // one drain path from another: its `action` argument names the row event
  // that ran, and exactly one action branch runs per call, so
  // `pending !== 0 && action === …` is precisely "a drain that could move
  // these sweeps happened". `toggle` writes `done`, which the two predicate
  // counts, the two predicate selections and the filter table read; `edit`,
  // `commit` and `keys` write `mode`, which the editing hint reads; `retype`
  // writes `draft`, which nothing but the persistence write-back reads — so
  // a keystroke inside a row editor lands in neither class.
  "    const region_touched_0 = regions[0][3] || regions[0][8][\"length\"] !== 0 || regions[0][4][\"length\"] !== 0;\n    const region_structural_0 = regions[0][3] || regions[0][8][\"length\"] !== 0;\n    const region_drain_0_0 = regions[0][3] || regions[0][8][\"length\"] !== 0 || regions[0][4][\"length\"] !== 0 && action === \"toggle\";\n    const region_drain_0_1 = regions[0][3] || regions[0][8][\"length\"] !== 0 || regions[0][4][\"length\"] !== 0 && (action === \"edit\" || action === \"commit\" || action === \"keys\");\n    const share_scan_0_0 = [0];\n    const share_scan_0_1 = [0];\n    if (region_drain_0_0) {\n      for (const share_row_0_0 of regions[0][1]) {\n        if (share_row_0_0[3] === \"false\") {\n          share_scan_0_0[0] += 1;\n        }\n        if (share_row_0_0[3] === \"true\") {\n          share_scan_0_1[0] += 1;\n        }\n      }\n    }\n    if (region_drain_0_0) {\n      tx[5] += 1;\n      tx[7][\"push\"](\"count:items:0:evaluated\");",
  "    if (region_drain_0_1) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"attr:6:hidden:evaluated\");\n      const hidden_scan_0_6 = [0];\n      for (const hidden_row_0_6 of regions[0][1]) {\n        if (hidden_row_0_6[4] === \"edit\") {",
  "    if (region_drain_0_0 || changed[1]) {",
  // The persistence write-back reads every field, so no class can narrow it:
  // it keeps the region-wide touched flag even in the dispatch function.
  "      regions[0][4] = [];\n    }\n    if (region_drain_0_0 || changed[1]) {",
  "    if (region_touched_0) {\n      const persist_rows_0 = [];",
  // ADR-0088: the region's predicate scans are grouped by the ADR-0083/0084
  // wake flag they already read, and a class holding two or more of them
  // walks the row table once, accumulating one cell per *distinct* field
  // equality. Outside the region's own dispatch function every sweep reads
  // the touched flag, so all five predicate scans — the two `done == "false"`
  // counts, the `done == "true"` clear-completed subject, the
  // `done == "false"` toggle-all subject and the `mode == "edit"` editing
  // hint — become one pass over three cells, and the two spellings of
  // `done == "false"` share cell 0.
  "    const region_structural_0 = regions[0][3] || regions[0][8][\"length\"] !== 0;\n    const share_scan_0_0 = [0];\n    const share_scan_0_1 = [0];\n    const share_scan_0_2 = [0];\n    if (region_touched_0) {\n      for (const share_row_0_0 of regions[0][1]) {\n        if (share_row_0_0[3] === \"false\") {\n          share_scan_0_0[0] += 1;\n        }\n        if (share_row_0_0[3] === \"true\") {\n          share_scan_0_1[0] += 1;\n        }\n        if (share_row_0_0[4] === \"edit\") {\n          share_scan_0_2[0] += 1;\n        }\n      }\n    }",
  // Inside the dispatch function the classes split, and the pass splits with
  // them: drain class 0 (`toggle`, which writes `done`) carries one pass over
  // two cells, and the editing hint keeps its own loop under drain class 1
  // rather than being dragged awake by the wider class. Nothing crosses a
  // class boundary — that is the whole contract, and the survey priced the
  // widening at 40% of the opportunity.
  "    if (region_drain_0_1) {\n      tx[8] += 1;\n      tx[7][\"push\"](\"attr:6:hidden:evaluated\");\n      const hidden_scan_0_6 = [0];\n      for (const hidden_row_0_6 of regions[0][1]) {\n        if (hidden_row_0_6[4] === \"edit\") {\n          hidden_scan_0_6[0] += 1;\n        }\n      }\n      const attr_next_6 = hidden_scan_0_6[0] === 0;",
  // A predicate-free total is a `length` read, not a scan: it joins no pass.
  "      const count_next_0_2 = regions[0][1][\"length\"];",
  // Each slot keeps its own cache, compare, write, label and counter — what
  // is shared is the traversal, not the cache.
  "      const count_next_0_0 = share_scan_0_0[0];",
  "      const count_next_0_1 = share_scan_0_0[0];",
]) {
  if (!source.includes(required)) {
    throw new Error(`generated Toggle Lab is missing ${required}`);
  }
}

const generated = await import(pathToFileURL(path.join(directory, "ToggleLab.mjs")).href);
if (typeof generated.mount !== "function") {
  throw new Error("generated Toggle Lab does not export mount");
}

console.log("generated Toggle Lab artifacts passed");
