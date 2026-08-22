import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

const directory = process.argv[2];
if (!directory) throw new Error("expected generated Issue Browser directory");

const manifest = JSON.parse(
  await readFile(path.join(directory, "IssueBrowser.mjs.manifest.json"), "utf8"),
);
const expectedPort = {
  name: "decodeIssueResponse",
  input: "record<HttpResponse>",
  output: "record<IssuePage>",
  mode: "sync",
  cancellation: "none",
  errors: ["LRX-PORT-302", "LRX-PORT-303", "LRX-PORT-304"],
  trust: "browser status/JSON parsing and object validation remain in the backend TCB",
  security: "JSON is parsed as data; unique safe IDs key rows and titles remain text",
};
if (
  manifest.module !== "IssueBrowser.mjs" ||
  manifest.runtimeAbi !== 8 ||
  JSON.stringify(manifest.stateSlots) !==
    JSON.stringify(["string", "list<record<Issue>>", "nat", "bool"]) ||
  manifest.sourceCount !== 4 ||
  manifest.derivedCount !== 0 ||
  manifest.eventCount !== 4 ||
  JSON.stringify(manifest.ports) !== JSON.stringify([expectedPort]) ||
  !manifest.features.includes("http") ||
  !manifest.features.includes("resource") ||
  !manifest.features.includes("pagination") ||
  !manifest.features.includes("owned-cancellation") ||
  JSON.stringify(manifest.hostImports) !== JSON.stringify([
    "./leanrx_dom.mjs",
    "./leanrx_host.mjs",
    "./leanrx_region.mjs",
    "./leanrx_effects.mjs",
    "./leanrx_issue_ports.mjs",
  ])
) {
  throw new Error("generated Issue Browser manifest is invalid");
}

const expected = JSON.parse(
  await readFile(path.join(directory, "IssueBrowser.expected.json"), "utf8"),
);
if (
  expected.url !== "/api/issues" ||
  expected.query !== "lean" ||
  expected.page !== "1" ||
  expected.handle !== "cmd-0" ||
  expected.firstIssue.id !== 1 ||
  expected.hasMore !== true ||
  expected.loadedStatus !== "Loaded 1 issues" ||
  expected.httpFailureStatus !== "Request failed: issue request returned HTTP 503"
) {
  throw new Error("native Issue Browser request/decoder artifact drifted");
}

const source = await readFile(path.join(directory, "IssueBrowser.mjs"), "utf8");
for (const banned of ["currentObserver", "new Proxy", "eval(", "Function(", "innerHTML"]) {
  if (source.includes(banned)) throw new Error(`generated Issue Browser contains ${banned}`);
}
for (const required of [
  "createEffectRuntime", "decodeIssueResponse", "createKeyedRegion", "makeEffectDisposer",
]) {
  if (!source.includes(required)) throw new Error(`generated Issue Browser lost ${required}`);
}

const generated = await import(pathToFileURL(path.join(directory, "IssueBrowser.mjs")).href);
if (JSON.stringify(Object.keys(generated)) !== JSON.stringify(["mount"])) {
  throw new Error("Issue Browser exposed internal handlers");
}

console.log("generated Issue Browser artifacts passed");
