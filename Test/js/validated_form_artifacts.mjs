import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Validated Form directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "ValidatedForm.mjs.manifest.json"), "utf8"),
);
if (
  manifest.module !== "ValidatedForm.mjs" ||
  manifest.runtimeAbi !== 18 ||
  JSON.stringify(manifest.stateSlots) !== JSON.stringify(["string", "string", "bool"]) ||
  manifest.sourceCount !== 3 ||
  manifest.derivedCount !== 0 ||
  manifest.textSinkCount !== 4 ||
  manifest.eventCount !== 8 ||
  !manifest.features.includes("typed-command") ||
  !manifest.features.includes("submit") ||
  !manifest.features.includes("checked") ||
  JSON.stringify(manifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./leanrx_form_events.mjs"])
) {
  throw new Error("generated Validated Form manifest is invalid");
}

const source = await readFile(path.join(directory, "ValidatedForm.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function(", "innerHTML"]) {
  if (source.includes(banned)) throw new Error(`generated Validated Form contains ${banned}`);
}
if (
  !source.includes('/^[0-9]+$/["test"](state[1])') ||
  !source.includes("listenSubmit") ||
  !source.includes("listenChecked") ||
  !source.includes("command:fakeSubmit")
) {
  throw new Error("generated Validated Form lost its checked submit path");
}

const generated = await import(pathToFileURL(path.join(directory, "ValidatedForm.mjs")).href);
if (JSON.stringify(Object.keys(generated)) !== JSON.stringify(["mount"])) {
  throw new Error("Validated Form exposed an unchecked submit function");
}

console.log("generated Validated Form artifacts passed");
