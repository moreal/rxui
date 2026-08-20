import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Notes directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "Notes.mjs.manifest.json"), "utf8"),
);
if (
  manifest.module !== "Notes.mjs" ||
  manifest.runtimeAbi !== 7 ||
  JSON.stringify(manifest.stateSlots) !== JSON.stringify(["string"]) ||
  manifest.sourceCount !== 1 ||
  manifest.derivedCount !== 0 ||
  manifest.eventCount !== 1 ||
  !manifest.features.includes("commands") ||
  !manifest.features.includes("timer") ||
  !manifest.features.includes("storage") ||
  !manifest.features.includes("owned-cancellation") ||
  JSON.stringify(manifest.hostImports) !== JSON.stringify([
    "./leanrx_dom.mjs",
    "./leanrx_host.mjs",
    "./leanrx_effects.mjs",
  ])
) {
  throw new Error("generated Notes manifest is invalid");
}

const expected = JSON.parse(await readFile(path.join(directory, "Notes.expected.json"), "utf8"));
if (
  expected.storageKey !== "leanrx.notes" ||
  expected.debounceMs !== 250 ||
  expected.initialStatus !== "Not saved" ||
  expected.waitingStatus !== "Waiting to save" ||
  expected.saveFailureStatus !== "Save failed: quota exceeded" ||
  expected.restoreFailureStatus !== "Restore failed: restore broke"
) {
  throw new Error("native Notes command artifact drifted");
}

const source = await readFile(path.join(directory, "Notes.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function(", "innerHTML"]) {
  if (source.includes(banned)) throw new Error(`generated Notes contains ${banned}`);
}
for (const required of [
  "createEffectRuntime", "storageGet", "storageSet", "timeout", "makeEffectDisposer",
]) {
  if (!source.includes(required)) throw new Error(`generated Notes lost ${required}`);
}

const generated = await import(pathToFileURL(path.join(directory, "Notes.mjs")).href);
if (JSON.stringify(Object.keys(generated)) !== JSON.stringify(["mount"])) {
  throw new Error("Notes exposed internal handlers");
}

console.log("generated Notes artifacts passed");
