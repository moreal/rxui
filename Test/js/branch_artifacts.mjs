import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Branch Lab directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "BranchLab.mjs.manifest.json"), "utf8"),
);
if (
  manifest.compilerVersion !== "0.1.0-dev" ||
  manifest.module !== "BranchLab.mjs" ||
  typeof manifest.graphHash !== "string" ||
  manifest.graphHash.length === 0 ||
  manifest.runtimeAbi !== 17 ||
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
  throw new Error("generated Branch Lab manifest is invalid");
}

const source = await readFile(path.join(directory, "BranchLab.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function("]) {
  if (source.includes(banned)) {
    throw new Error(`generated Branch Lab contains ${banned}`);
  }
}
for (const required of [
  // ADR-0047: replacement composes from the detach/append host primitives;
  // ADR-0048 joins them with the ABI 16 focus export on the DOM host.
  "import { createElement, createText, setAttribute, append, listen, setText, makeDisposer, setProperty, setKey, childAt, listenDelegatedCells, focus } from \"./leanrx_dom.mjs\";",
  "import { createKeyedRegion, detach } from \"./leanrx_region.mjs\";",
  // Both sealed branch subtrees are dedicated builder functions shared by the
  // row mount conditional and the update callback's replacement arm.
  "function $lrx_region_0_branch_0_t(item) {",
  "function $lrx_region_0_branch_0_f(item) {",
  // The branch cell mounts as one wrapper span carrying the rendered branch
  // as the compiler-owned $lrxBranch marker (the setKey style).
  "  const row_2 = item[3] === \"view\";",
  "  append(row_1, row_2 ? $lrx_region_0_branch_0_t(item) : $lrx_region_0_branch_0_f(item));",
  "  setProperty(row_1, \"$lrxBranch\", row_2);",
  // The retained-row update callback updates the stable branch in place and
  // replaces the subtree only on a branch change.
  "  const branch_cell_0 = childAt(row, 0);",
  "  const branch_want_0 = item[3] === \"view\";",
  "  const branch_same_0 = branch_cell_0[\"$lrxBranch\"] === branch_want_0;",
  "    detach(childAt(branch_cell_0, 0));",
  "    append(branch_cell_0, branch_want_0 ? $lrx_region_0_branch_0_t(item) : $lrx_region_0_branch_0_f(item));",
  // ADR-0048: only the replacement arm focuses, and only when the incoming
  // branch is the autoFocus-marked edit input.
  "    if (!branch_want_0) {\n      focus(childAt(branch_cell_0, 0));\n    }",
  // ADR-0047 row value reflection: the edit input's value property follows
  // the draft field at branch mount and in the stable-branch update arm.
  "  setProperty(row_0, \"value\", item[2]);",
  "      setProperty(childAt(branch_cell_0, 0), \"value\", item[2]);",
  // Delegated bindings stay static across branches: the input action is drawn
  // from the edit branch while every click action sits in an unbranched cell.
  "const region_off_0 = listenDelegatedCells(node_7, \"click\", state, context, $lrx_region_0_dispatch, [\"\", \"edit\", \"commit\", \"remove\"]);",
  "const region_off_0_input = listenDelegatedCells(node_7, \"input\", state, context, $lrx_region_0_dispatch, [\"retype\", \"\", \"\", \"\"]);",
  "makeDisposer(node_0, [off_0, region_off_0, region_off_0_input, region_0[\"dispose\"]], tx, [region_0])",
]) {
  if (!source.includes(required)) {
    throw new Error(`generated Branch Lab is missing ${required}`);
  }
}

// Row mount never focuses (ADR-0048): the single focus call site lives in
// the update callback's replacement arm.
if (source.split("\n      focus(").length !== 2) {
  throw new Error("generated Branch Lab must call focus exactly once");
}

const generated = await import(pathToFileURL(path.join(directory, "BranchLab.mjs")).href);
if (typeof generated.mount !== "function") {
  throw new Error("generated Branch Lab does not export mount");
}

console.log("generated Branch Lab artifacts passed");
