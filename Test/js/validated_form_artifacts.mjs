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
  manifest.runtimeAbi !== 20 ||
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

// ADR-0105: three controlled controls, three declarations. `name` and `age`
// are ADR-0038 text bindings and `terms` is a `checked` binding, which is the
// same three-way split the checked pipeline covers -- and the submit button
// and the two error paragraphs, which the program only ever writes `disabled`
// and text into, declare nothing.
for (const required of [
  '  setAttribute(nameInput, "autocomplete", "off");\n  setProperty(nameInput, "value",',
  '  setAttribute(ageInput, "autocomplete", "off");\n  setProperty(ageInput, "value",',
  '  setAttribute(termsInput, "autocomplete", "off");\n  setProperty(termsInput, "checked",',
]) {
  if (!source.includes(required)) {
    throw new Error(`generated Validated Form is missing ${required}`);
  }
}
{
  const declared = source.split('"autocomplete", "off"').length - 1;
  if (declared !== 3) {
    throw new Error(`generated Validated Form declares ${declared} owned controls, expected 3`);
  }
}

const generated = await import(pathToFileURL(path.join(directory, "ValidatedForm.mjs")).href);
if (JSON.stringify(Object.keys(generated)) !== JSON.stringify(["mount"])) {
  throw new Error("Validated Form exposed an unchecked submit function");
}

console.log("generated Validated Form artifacts passed");
