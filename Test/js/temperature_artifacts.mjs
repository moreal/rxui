import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Temperature Converter directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "TemperatureConverter.mjs.manifest.json"), "utf8"),
);
if (
  manifest.module !== "TemperatureConverter.mjs" ||
  manifest.runtimeAbi !== 20 ||
  JSON.stringify(manifest.stateSlots) !== JSON.stringify(["string", "string", "bool"]) ||
  manifest.sourceCount !== 3 ||
  manifest.derivedCount !== 0 ||
  manifest.textSinkCount !== 1 ||
  manifest.eventCount !== 2 ||
  !manifest.features.includes("controlled-input") ||
  !manifest.features.includes("validation") ||
  JSON.stringify(manifest.hostImports) !==
    JSON.stringify(["./leanrx_dom.mjs", "./leanrx_form_events.mjs"])
) {
  throw new Error("generated Temperature Converter manifest is invalid");
}

const source = await readFile(path.join(directory, "TemperatureConverter.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function(", "innerHTML"]) {
  if (source.includes(banned)) throw new Error(`generated temperature module contains ${banned}`);
}
if (
  !source.includes('/^-?[0-9]+$/["test"](activeRaw)') ||
  !source.includes("BigInt(activeRaw)") ||
  !source.includes("listenValue")
) {
  throw new Error("generated temperature parser/payload path is incomplete");
}

// ADR-0105: the hand-written backend makes the ADR-0104 ownership claim in
// the same words the checked pipeline uses. Both inputs have their `value`
// rewritten from the state cell on every conversion, so both declare it --
// last static attribute, directly before the owned property write.
for (const required of [
  '  setAttribute(celsiusInput, "aria-invalid", "false");\n'
    + '  setAttribute(celsiusInput, "autocomplete", "off");\n'
    + '  setProperty(celsiusInput, "value", "0");',
  '  setAttribute(fahrenheitInput, "aria-invalid", "false");\n'
    + '  setAttribute(fahrenheitInput, "autocomplete", "off");\n'
    + '  setProperty(fahrenheitInput, "value", "32");',
]) {
  if (!source.includes(required)) {
    throw new Error(`generated Temperature Converter is missing ${required}`);
  }
}
{
  const declared = source.split('"autocomplete", "off"').length - 1;
  if (declared !== 2) {
    throw new Error(
      `generated Temperature Converter declares ${declared} owned controls, expected 2`,
    );
  }
}

const generated = await import(
  pathToFileURL(path.join(directory, "TemperatureConverter.mjs")).href,
);
if (JSON.stringify(Object.keys(generated)) !== JSON.stringify(["mount"])) {
  throw new Error("Temperature Converter exposed unchecked handlers");
}

console.log("generated Temperature Converter artifacts passed");
