import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) {
  throw new Error("expected Expression Playground JavaScript directory");
}

const expected = JSON.parse(
  await readFile(path.join(directory, "expected.json"), "utf8"),
);
const subtotal = await import(pathToFileURL(path.join(directory, "subtotal.mjs")).href);
const isLarge = await import(pathToFileURL(path.join(directory, "is_large.mjs")).href);
const label = await import(pathToFileURL(path.join(directory, "label.mjs")).href);

for (const [moduleName, exportName, resultType] of [
  ["subtotal.mjs", "subtotal", "int"],
  ["is_large.mjs", "isLarge", "bool"],
  ["label.mjs", "label", "string"],
]) {
  const manifest = JSON.parse(
    await readFile(path.join(directory, `${moduleName}.manifest.json`), "utf8"),
  );
  if (
    manifest.module !== moduleName ||
    manifest.runtimeAbi !== 13 ||
    JSON.stringify(manifest.exports) !== JSON.stringify([exportName]) ||
    manifest.inputs.map((input) => input.type).join(",") !== "int,int,int" ||
    manifest.resultType !== resultType
  ) {
    throw new Error(`invalid Expression Playground artifact manifest: ${moduleName}`);
  }
}

const inputs = [
  [12n, 4n, 40n],
  [5n, 4n, 40n],
];

for (const [index, values] of inputs.entries()) {
  const actual = {
    name: expected[index].name,
    subtotal: subtotal.subtotal(...values).toString(),
    isLarge: isLarge.isLarge(...values),
    label: label.label(...values),
  };
  if (JSON.stringify(actual) !== JSON.stringify(expected[index])) {
    throw new Error(
      `Expression Playground differential mismatch: expected ${JSON.stringify(expected[index])}, ` +
        `got ${JSON.stringify(actual)}`,
    );
  }
  console.log(`${actual.name} subtotal: ${actual.subtotal}`);
  console.log(`${actual.name} isLarge: ${actual.isLarge}`);
  console.log(`${actual.name} label: ${actual.label}`);
}
