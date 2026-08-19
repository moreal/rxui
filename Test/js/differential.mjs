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
  const moduleUrl = pathToFileURL(path.join(directory, testCase.module)).href;
  const generated = await import(moduleUrl);
  const actual = encode(generated[testCase.export](...testCase.args.map(decode)));
  if (JSON.stringify(actual) !== JSON.stringify(testCase.expected)) {
    throw new Error(
      `differential mismatch at case ${index} (${testCase.module}): ` +
        `expected ${JSON.stringify(testCase.expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

console.log(`native/JavaScript differential cases passed: ${cases.length}`);
