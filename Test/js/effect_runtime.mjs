import { createEffectRuntime } from "../../runtime/leanrx_effects.mjs";

const metrics = [0, 0, 0, 0, 0, 0, 0, [], 0, 0];
const storageValues = new Map([["present", "saved"]]);
const storage = {
  getItem(key) {
    if (key === "read-error") throw new Error("read denied");
    return storageValues.get(key) ?? null;
  },
  setItem(key, value) {
    if (key === "write-error") throw new Error("quota");
    storageValues.set(key, value);
  },
};

const pending = new Map();
function fetchMock(url, options) {
  return new Promise((resolve, reject) => {
    const abort = () => reject(new DOMException("aborted", "AbortError"));
    options.signal.addEventListener("abort", abort, { once: true });
    pending.set(url, { resolve, reject, abort });
  });
}

let foreignCancelled = 0;
let resolveForeign;
const ports = {
  uppercase: { run: (value) => value.toUpperCase() },
  deferred: {
    run: () => ({
      promise: new Promise((resolve) => { resolveForeign = resolve; }),
      cancel: () => { foreignCancelled += 1; },
    }),
  },
};

const runtime = createEffectRuntime(metrics, { storage, fetch: fetchMock, ports });
const delivered = [];
const deliver = (name) => (_, __, handle, result) => delivered.push({ name, handle, result });
const drain = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await new Promise((resolve) => setTimeout(resolve, 0));
};

runtime.storageGet("read", "present", null, null, deliver("read"));
runtime.storageGet("missing", "absent", null, null, deliver("missing"));
runtime.storageGet("read-fail", "read-error", null, null, deliver("read-fail"));
runtime.storageSet("write", "draft", "text", null, null, deliver("write"));
runtime.storageSet("write-fail", "write-error", "text", null, null, deliver("write-fail"));
runtime.foreign("upper", "uppercase", "leanrx", null, null, deliver("upper"));
await drain();

const resultFor = (name) => delivered.find((entry) => entry.name === name)?.result;
if (delivered.length !== 6 || resultFor("read").value.value !== "saved" ||
    resultFor("missing").value.kind !== "missing" ||
    resultFor("read-fail").error.code !== "LRX-STORAGE-001" ||
    storageValues.get("draft") !== "text" ||
    resultFor("write-fail").error.code !== "LRX-STORAGE-002" ||
    resultFor("upper").value !== "LEANRX") {
  throw new Error(`effect adapter result drifted: ${JSON.stringify(delivered)}`);
}

runtime.http("old", {
  method: "GET",
  url: "/api/issues",
  query: [["q", "old & unsafe"], ["page", "1"]],
}, null, null, deliver("old"));
await drain();
if (!pending.has("/api/issues?q=old+%26+unsafe&page=1")) {
  throw new Error("HTTP query was not encoded by the owned adapter");
}
runtime.cancel("old");
await drain();
if (delivered.length !== 6) throw new Error("cancelled HTTP request delivered a result");

runtime.foreign("deferred", "deferred", null, null, null, deliver("deferred"));
runtime.cancel("deferred");
resolveForeign("late");
await drain();
if (foreignCancelled !== 1 || delivered.length !== 6) {
  throw new Error("cancelled foreign operation delivered or skipped its cancel handle");
}

runtime.http("dispose-http", { method: "GET", url: "/dispose", query: [] },
  null, null, deliver("dispose-http"));
runtime.foreign("dispose-port", "deferred", null, null, null, deliver("dispose-port"));
await drain();
runtime.dispose();
runtime.dispose();
resolveForeign("after-dispose");
await drain();
if (delivered.length !== 6 || JSON.stringify(runtime.instrumentation()) !== "[10,4]") {
  throw new Error(`disposal/counters drifted: ${JSON.stringify(runtime.instrumentation())}`);
}

runtime.storageGet("after-dispose", "present", null, null, deliver("after-dispose"));
await drain();
if (delivered.length !== 6) throw new Error("post-disposal command was started");

console.log("effect runtime contract passed");
