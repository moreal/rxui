import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Diamond Lab directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "DiamondLab.mjs.manifest.json"), "utf8"),
);
if (
  manifest.module !== "DiamondLab.mjs" ||
  JSON.stringify(manifest.stateSlots) !== JSON.stringify(["int", "int", "int", "int"]) ||
  manifest.sourceCount !== 1 ||
  manifest.derivedCount !== 3 ||
  manifest.textSinkCount !== 3 ||
  manifest.eventCount !== 1 ||
  !manifest.features.includes("transactions") ||
  !manifest.features.includes("instrumentation")
) {
  throw new Error("generated Diamond Lab manifest is invalid");
}

const expected = JSON.parse(
  await readFile(path.join(directory, "Diamond.expected.json"), "utf8"),
);
if (
  expected.initialTotal !== 13 ||
  expected.finalTotal !== 19 ||
  expected.derivedEvaluations !== 3 ||
  expected.sinkEvaluations !== 1
) {
  throw new Error("Diamond native reference artifact changed");
}

const generated = await import(
  pathToFileURL(path.join(directory, "DiamondLab.mjs")).href
);
if (typeof generated.mount !== "function") {
  throw new Error("generated Diamond Lab does not export mount");
}

console.log("generated Diamond Lab artifacts passed");
