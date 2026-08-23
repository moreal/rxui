import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) {
  throw new Error("expected generated-JavaScript directory");
}

const cases = JSON.parse(await readFile(path.join(directory, "cases.json"), "utf8"));

function decode(value) {
  switch (value.type) {
    case "bool":
    case "string":
      return value.value;
    case "bigint":
      return BigInt(value.value);
    case "number":
      return value.value;
    case "array":
      return value.value.map(decode);
    default:
      throw new Error(`unknown manifest value type: ${value.type}`);
  }
}

function encode(value) {
  switch (typeof value) {
    case "boolean":
      return { type: "bool", value };
    case "string":
      return { type: "string", value };
    case "bigint":
      return { type: "bigint", value: value.toString() };
    default:
      throw new Error(`unsupported generated result type: ${typeof value}`);
  }
}

for (const [index, testCase] of cases.entries()) {
  const variants = [
    testCase.module,
    testCase.module.replace(/\.mjs$/, ".compact.mjs"),
  ];
  for (const variant of variants) {
    const artifact = JSON.parse(
      await readFile(path.join(directory, `${variant}.manifest.json`), "utf8"),
    );
    if (
      artifact.compilerVersion !== "0.1.0-dev" ||
      artifact.leanToolchain !== "leanprover/lean4:v4.33.0" ||
      artifact.module !== variant ||
      artifact.runtimeAbi !== 14 ||
      JSON.stringify(artifact.exports) !== JSON.stringify([testCase.export]) ||
      artifact.inputs.length !== testCase.args.length ||
      !["bool", "string", "int", "nat"].includes(artifact.resultType) ||
      JSON.stringify(artifact.features) !== JSON.stringify(["scalar"])
    ) {
      throw new Error(`invalid scalar artifact manifest for ${variant}`);
    }
    if (
      testCase.module === "hostile_names.mjs" &&
      artifact.inputs[0].generatedName !== "eval_"
    ) {
      throw new Error(`hostile input name was not recorded after mangling: ${variant}`);
    }
    const moduleUrl = pathToFileURL(path.join(directory, variant)).href;
    const generated = await import(moduleUrl);
    const actual = encode(generated[testCase.export](...testCase.args.map(decode)));
    if (JSON.stringify(actual) !== JSON.stringify(testCase.expected)) {
      throw new Error(
        `differential mismatch at case ${index} (${variant}): ` +
          `expected ${JSON.stringify(testCase.expected)}, got ${JSON.stringify(actual)}`,
      );
    }
  }
}

console.log(`native/JavaScript differential cases passed: ${cases.length} × 2 printer modes`);
