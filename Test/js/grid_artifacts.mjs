import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated data-grid directory");

const manifest = JSON.parse(fs.readFileSync(path.join(directory, "DataGrid.mjs.manifest.json"), "utf8"));
const expected = JSON.parse(fs.readFileSync(path.join(directory, "DataGrid.expected.json"), "utf8"));
const readable = fs.readFileSync(path.join(directory, "DataGrid.mjs"), "utf8");
const compact = fs.readFileSync(path.join(directory, "DataGrid.min.mjs"), "utf8");

if (manifest.runtimeAbi !== 7 || manifest.module !== "DataGrid.mjs" ||
    JSON.stringify(manifest.exports) !== '["mountFull","mountDelta","mountHybrid"]' ||
    manifest.graphHash !== "grid:10000:5000:10:1:9998:7777:256:8:3:1" ||
    !manifest.features.includes("structural-delta") ||
    !manifest.features.includes("hybrid-cost-model") ||
    manifest.eventCount !== 7 || manifest.sourceCount !== 4 || manifest.derivedCount !== 1) {
  throw new Error("data-grid manifest contract changed");
}
if (JSON.stringify(manifest.hostImports) !==
    '["./leanrx_dom.mjs","./leanrx_region.mjs","./leanrx_host.mjs"]') {
  throw new Error("data-grid host import contract changed");
}
if (expected.sourceCount !== 9000 || expected.visibleCount !== 5000 ||
    expected.firstId !== 9999 || expected.lastId !== 1 || expected.selected !== 7777 ||
    expected.operationCount !== 7 || expected.rows.length !== 5000 ||
    !expected.rows.every((row, index) => row[0] === 9999 - index * 2 &&
      row[1] === `Row ${row[0]} value ${row[0] * 10}` && row[2] === (row[0] === 7777))) {
  throw new Error("native data-grid oracle changed");
}
if (!readable.includes("createDeltaKeyedRegion") || !readable.includes("mountHybrid") ||
    !readable.includes('"table"') || !readable.includes('"cell"') ||
    !readable.includes("256") || !readable.includes("8") || !readable.includes("3") ||
    !readable.includes("0n") || compact.length >= readable.length ||
    /eval\(|Function\(|currentObserver|new Proxy|innerHTML/.test(readable)) {
  throw new Error("data-grid JavaScript artifact boundary changed");
}

console.log("generated Data Grid artifacts passed");
