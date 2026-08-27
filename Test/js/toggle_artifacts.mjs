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
  // ADR-0049/0050/0051/0052 ship with no host change: the ABI stays at the
  // ADR-0048 level.
  manifest.runtimeAbi !== 16 ||
  JSON.stringify(manifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(manifest.stateSlots) !== JSON.stringify(["int", "string"]) ||
  manifest.sourceCount !== 2 ||
  manifest.derivedCount !== 0 ||
  manifest.textSinkCount !== 1 ||
  manifest.eventCount !== 6 ||
  JSON.stringify(manifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./leanrx_region.mjs"]) ||
  JSON.stringify(manifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "keyed-regions", "typed-row-events", "row-key-branches", "row-guards",
    "row-trim", "row-branches", "row-reflects", "row-focus", "row-aggregates",
    "region-broadcasts", "region-filters",
  ])
) {
  throw new Error("generated Toggle Lab manifest is invalid");
}

const source = await readFile(path.join(directory, "ToggleLab.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function("]) {
  if (source.includes(banned)) {
    throw new Error(`generated Toggle Lab contains ${banned}`);
  }
}
for (const required of [
  // ADR-0049/0050/0051 ride the existing exports: the import line matches
  // Branch Lab's exactly — no new host export and no ABI bump for the kinds,
  // the aggregates, the broadcasts, or the filter view.
  "import { createElement, createText, setAttribute, append, listen, setText, makeDisposer, setProperty, setKey, childAt, listenDelegatedCells, focus } from \"./leanrx_dom.mjs\";",
  "import { createKeyedRegion, detach } from \"./leanrx_region.mjs\";",
  // One structural delegated listener per bound kind, in registration order,
  // each with its own static per-cell action array (ADR-0041/0046/0049).
  "const region_off_0 = listenDelegatedCells(node_22, \"click\", state, context, $lrx_region_0_dispatch, [\"\", \"\", \"commit\", \"remove\"]);",
  "const region_off_0_dblclick = listenDelegatedCells(node_22, \"dblclick\", state, context, $lrx_region_0_dispatch, [\"\", \"edit\", \"\", \"\"]);",
  "const region_off_0_input = listenDelegatedCells(node_22, \"input\", state, context, $lrx_region_0_dispatch, [\"\", \"retype\", \"\", \"\"]);",
  "const region_off_0_keydown = listenDelegatedCells(node_22, \"keydown\", state, context, $lrx_region_0_dispatch, [\"\", \"keys\", \"\", \"\"]);",
  "const region_off_0_change = listenDelegatedCells(node_22, \"change\", state, context, $lrx_region_0_dispatch, [\"toggle\", \"\", \"\", \"\"]);",
  // The ADR-0052 key-branched selection: one eventKey equality per arm
  // inside the existing action match — a matched key runs the ADR-0043
  // scan-evaluate-assign-queue sequence, a non-matching key falls through
  // to the shared commit with no scan, no write, and no trace.
  "  if (action === \"keys\") {\n    if (eventKey === \"Enter\") {",
  // The ADR-0053 remove-if guard on the Enter arm, with the ADR-0054 trim
  // contract: the guard equality and the committed label both evaluate the
  // ASCII-trimmed draft against the row the key scan resolved; the hit runs
  // the kept-filter removal the remove action uses, the miss commits the
  // trimmed assignment sequence.
  "      if (scan[1] !== -1) {\n        const row_item = regions[0][1][scan[1]];\n        const row_guard = row_item[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\") === \"\";\n        if (row_guard) {\n          const kept_0 = [];\n          for (const row_entry of regions[0][1]) {\n            if (row_entry[0] !== key) {\n              kept_0[\"push\"](row_entry);\n            }\n          }\n          regions[0][1] = kept_0;\n          regions[0][3] = true;\n          tx[7][\"push\"](\"region:items:keys\");\n        }\n        if (!row_guard) {\n          const row_next_0 = row_item[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\");\n          const row_next_1 = row_item[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\");\n          const row_next_2 = \"view\";\n          row_item[1] = row_next_0;\n          row_item[2] = row_next_1;\n          row_item[4] = row_next_2;\n          regions[0][4][\"push\"](scan[1]);\n          tx[7][\"push\"](\"region:items:keys\");\n        }\n      }\n    }\n    if (eventKey === \"Escape\") {",
  "        const row_next_0 = row_item[1];\n        const row_next_1 = \"view\";\n        row_item[2] = row_next_0;",
  // The ADR-0053 guarded commit with the ADR-0054 trim contract: the OK
  // button's action branch carries the same trimmed guard equality, trimmed
  // label commit, and removal sequence — destroy-on-whitespace-commit
  // through both commit paths, with the Escape revert arm unguarded and
  // untrimmed.
  "      const row_guard = row_item[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\") === \"\";\n      if (row_guard) {\n        const kept_0 = [];\n        for (const row_entry of regions[0][1]) {\n          if (row_entry[0] !== key) {\n            kept_0[\"push\"](row_entry);\n          }\n        }\n        regions[0][1] = kept_0;\n        regions[0][3] = true;\n        tx[7][\"push\"](\"region:items:commit\");\n      }\n      if (!row_guard) {\n        const row_next_0 = row_item[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\");\n        const row_next_1 = row_item[2][\"replace\"](/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g, \"\");\n        const row_next_2 = \"view\";\n        row_item[1] = row_next_0;\n        row_item[2] = row_next_1;\n        row_item[4] = row_next_2;\n        regions[0][4][\"push\"](scan[1]);\n        tx[7][\"push\"](\"region:items:commit\");\n      }",
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
  "makeDisposer(node_0, [off_0, off_1, off_2, off_3, off_4, off_5, region_off_0, region_off_0_dblclick, region_off_0_input, region_off_0_keydown, region_off_0_change, region_0[\"dispose\"]], tx, [region_0])",
  // The ADR-0050 region record carries the count refs and numeric cache in
  // two region-local slots behind the pending slot, and the ADR-0051 filter
  // slot holds the container element behind them.
  "const regions = [[region_0, [], 0, false, [], [count_text_19, count_text_21], [0, 0], node_22]];",
  // The broadcast writes every row from the sealed row expression and raises
  // the dirty flag; the predicate removal keeps the non-matching rows.
  "  for (const row_item of regions[0][1]) {\n    const row_next_0 = \"true\";\n    row_item[3] = row_next_0;\n  }\n  regions[0][3] = true;",
  "  const kept_0 = [];",
  "  regions[0][1] = kept_0;",
  // The count sweep reads the touched flag before the reconcile consumes
  // it, recomputes both count forms, and writes through setText.
  "    const region_touched_0 = regions[0][3] || regions[0][4][\"length\"] !== 0;",
  "      const count_next_0_1 = regions[0][1][\"length\"];",
  "        setText(regions[0][5][0], count_next_0_0);",
  // The ADR-0051 filter sweep runs after the reconcile and drain whenever
  // the region was touched or the filter field changed, writing each row
  // root's hidden property from the sealed state-to-predicate table by
  // childAt navigation from the record's container slot — the unmatched
  // "all" falls through to false.
  "    if (region_touched_0 || changed[1]) {",
  "        setProperty(childAt(regions[0][7], filter_scan_0[0]), \"hidden\", state[1] === \"active\" ? filter_row_0[3] !== \"false\" : state[1] === \"completed\" ? filter_row_0[3] !== \"true\" : false);",
  "      tx[7][\"push\"](\"filter:items:evaluated\");",
  "      tx[7][\"push\"](\"dom:filter:items:write\");",
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
