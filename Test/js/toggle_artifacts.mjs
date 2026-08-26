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
  // ADR-0049 ships with no host change: the ABI stays at the ADR-0048 level.
  manifest.runtimeAbi !== 16 ||
  JSON.stringify(manifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(manifest.stateSlots) !== JSON.stringify(["int"]) ||
  manifest.sourceCount !== 1 ||
  manifest.derivedCount !== 0 ||
  manifest.textSinkCount !== 1 ||
  manifest.eventCount !== 1 ||
  JSON.stringify(manifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./leanrx_region.mjs"]) ||
  JSON.stringify(manifest.features) !== JSON.stringify([
    "scalar", "events", "transactions", "instrumentation", "trace",
    "keyed-regions", "typed-row-events", "row-branches", "row-reflects",
    "row-focus",
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
  // ADR-0049 rides the existing exports: the import line matches Branch
  // Lab's exactly — no new host export and no ABI bump for the two kinds.
  "import { createElement, createText, setAttribute, append, listen, setText, makeDisposer, setProperty, setKey, childAt, listenDelegatedCells, focus } from \"./leanrx_dom.mjs\";",
  "import { createKeyedRegion, detach } from \"./leanrx_region.mjs\";",
  // One structural delegated listener per bound kind, in registration order,
  // each with its own static per-cell action array (ADR-0041/0046/0049).
  "const region_off_0 = listenDelegatedCells(node_7, \"click\", state, context, $lrx_region_0_dispatch, [\"\", \"\", \"commit\", \"remove\"]);",
  "const region_off_0_dblclick = listenDelegatedCells(node_7, \"dblclick\", state, context, $lrx_region_0_dispatch, [\"\", \"edit\", \"\", \"\"]);",
  "const region_off_0_input = listenDelegatedCells(node_7, \"input\", state, context, $lrx_region_0_dispatch, [\"\", \"retype\", \"\", \"\"]);",
  "const region_off_0_change = listenDelegatedCells(node_7, \"change\", state, context, $lrx_region_0_dispatch, [\"toggle\", \"\", \"\", \"\"]);",
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
  "makeDisposer(node_0, [off_0, region_off_0, region_off_0_dblclick, region_off_0_input, region_off_0_change, region_0[\"dispose\"]], tx, [region_0])",
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
