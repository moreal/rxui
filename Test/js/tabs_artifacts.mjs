import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Dependent Tabs directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "DependentTabs.mjs.manifest.json"), "utf8"),
);
if (
  manifest.compilerVersion !== "0.1.0-dev" ||
  manifest.leanToolchain !== "leanprover/lean4:v4.33.0" ||
  manifest.module !== "DependentTabs.mjs" ||
  manifest.runtimeAbi !== 11 ||
  JSON.stringify(manifest.exports) !== JSON.stringify(["mount"]) ||
  JSON.stringify(manifest.stateSlots) !== JSON.stringify(["fin<3>"]) ||
  manifest.sourceCount !== 1 ||
  manifest.derivedCount !== 0 ||
  manifest.textSinkCount !== 1 ||
  manifest.eventCount !== 1 ||
  JSON.stringify(manifest.features) !==
    JSON.stringify([
      "dependent",
      "immutable-props",
      "typed-events",
      "proof-erasure",
      "direct-dom",
      "actual-change",
      "instrumentation",
      "trace",
    ])
) {
  throw new Error("generated Dependent Tabs manifest is invalid");
}

const source = await readFile(path.join(directory, "DependentTabs.mjs"), "utf8");
for (const banned of [
  "proof",
  "isLt",
  "Nat.zero_lt_succ",
  "Vector.",
  "Fin.",
  "currentObserver",
  "new Proxy",
  "eval(",
  "Function(",
]) {
  if (source.includes(banned)) {
    throw new Error(`generated Dependent Tabs contains erased/banned text: ${banned}`);
  }
}
if (
  !source.includes("return panels[selected];") ||
  !source.includes("return $lrx_select(state, context, 0);") ||
  !source.includes("return $lrx_select(state, context, 2);") ||
  source.includes("$lrx_select_3")
) {
  throw new Error("generated finite event handlers are incomplete or out of range");
}

const generated = await import(
  pathToFileURL(path.join(directory, "DependentTabs.mjs")).href,
);
if (JSON.stringify(Object.keys(generated)) !== JSON.stringify(["mount"])) {
  throw new Error("Dependent Tabs exposed an unchecked event entry point");
}

console.log("generated Dependent Tabs artifacts passed");
