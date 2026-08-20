import {
  createEffectRuntime,
  makeEffectDisposer,
} from "../../runtime/leanrx_effects.mjs";
import { decodeIssueResponse } from "../../runtime/leanrx_issue_ports.mjs";

const unhandled = [];
const captureUnhandled = (reason) => unhandled.push(reason);
process.on("unhandledRejection", captureUnhandled);

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
    resultFor("read-fail").error.code !== "LRX-PORT-201" ||
    storageValues.get("draft") !== "text" ||
    resultFor("write-fail").error.code !== "LRX-PORT-202" ||
    resultFor("upper").value !== "LEANRX") {
  throw new Error(`effect adapter result drifted: ${JSON.stringify(delivered)}`);
}

runtime.http("old", "GET", "/api/issues",
  [["q", "old & unsafe"], ["page", "1"]], null, null, null, deliver("old"));
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

runtime.http("dispose-http", "GET", "/dispose", [], null,
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

const wrapperMetrics = [0, 0, 0, 0, 0, 0, 0, [], 0, 0];
const wrapperRuntime = createEffectRuntime(wrapperMetrics, { storage, fetch: fetchMock, ports });
const wrapperState = [false];
let baseDisposed = 0;
const baseDisposer = () => { baseDisposed += 1; };
baseDisposer.instrumentation = () => ["base"];
baseDisposer.regionInstrumentation = () => [];
wrapperRuntime.foreign("owned", "deferred", null, null, null, deliver("owned"));
const wrapped = makeEffectDisposer(baseDisposer, wrapperState, 0, wrapperRuntime);
wrapped();
wrapped();
if (!wrapperState[0] || baseDisposed !== 1 || foreignCancelled !== 3 ||
    JSON.stringify(wrapped.instrumentation()) !== '["base"]' ||
    JSON.stringify(wrapped.effectInstrumentation()) !== "[1,1]") {
  throw new Error("effect disposer did not cancel and delegate exactly once");
}

const decoded = decodeIssueResponse({
  status: 200,
  body: '{"issues":[{"id":7,"title":"typed"}],"hasMore":true}',
});
const invalid = decodeIssueResponse({ status: 200, body: '{"issues":"wrong"}' });
const statusFailure = decodeIssueResponse({ status: 503, body: "{}" });
if (JSON.stringify(decoded) !==
    '{"ok":true,"value":[[[7,"typed"]],true]}' ||
    invalid.error.code !== "LRX-HTTP-DECODE-001" ||
    statusFailure.error.code !== "LRX-HTTP-STATUS-001") {
  throw new Error("issue decoder port drifted from its typed wire contract");
}

let replacementCancels = 0;
const replacementResolvers = [];
const replacementMetrics = [0, 0, 0, 0, 0, 0, 0, [], 0, 0];
const replacementRuntime = createEffectRuntime(replacementMetrics, { ports: {
  replacement: {
    run: () => ({
      promise: new Promise((resolve) => replacementResolvers.push(resolve)),
      cancel: () => { replacementCancels += 1; },
    }),
  },
} });
const replacementDelivered = [];
const replacementDeliver = (_, __, ___, result) => replacementDelivered.push(result.value);
replacementRuntime.foreign("same", "replacement", "old", null, null, replacementDeliver);
replacementRuntime.foreign("same", "replacement", "new", null, null, replacementDeliver);
replacementResolvers[0]("stale");
await drain();
replacementResolvers[1]("fresh");
await drain();
if (replacementCancels !== 1 || JSON.stringify(replacementDelivered) !== '["fresh"]' ||
    JSON.stringify(replacementRuntime.instrumentation()) !== "[2,1]") {
  throw new Error("same-handle replacement accepted a stale operation completion");
}

const failureMetrics = [0, 0, 0, 0, 0, 0, 0, [], 0, 0];
const failureRuntime = createEffectRuntime(failureMetrics, {
  fetch: () => Promise.reject(new Error("network down")),
  ports: { rejecting: { run: () => Promise.reject(Object.create(null)) } },
});
const failures = [];
const failureDeliver = (_, __, handle, result) => failures.push([handle, result]);
failureRuntime.foreign("missing", "absent", null, null, null, failureDeliver);
failureRuntime.foreign("rejecting", "rejecting", null, null, null, failureDeliver);
failureRuntime.http("network", "GET", "/network", [], null, null, null, failureDeliver);
await drain();
const failureCodes = failures.map(([, result]) => result.error.code).sort();
if (JSON.stringify(failureCodes) !==
      '["LRX-PORT-301","LRX-PORT-401","LRX-PORT-402"]' ||
    unhandled.length !== 0) {
  throw new Error(`effect failures escaped or drifted: ${JSON.stringify(failureCodes)}`);
}

let cleanupRuntime;
let cleanupBaseCalls = 0;
const cleanupMetrics = [0, 0, 0, 0, 0, 0, 0, [], 0, 0];
const never = () => new Promise(() => {});
cleanupRuntime = createEffectRuntime(cleanupMetrics, { ports: {
  throwingCancel: { run: () => ({ promise: never(), cancel: () => { throw new Error("boom"); } }) },
  reentrantCancel: {
    run: () => ({ promise: never(), cancel: () => cleanupRuntime.cancel("reentrant") }),
  },
  rejectingCancel: {
    run: () => ({ promise: never(), cancel: () => Promise.reject(Object.create(null)) }),
  },
} });
cleanupRuntime.foreign("throwing", "throwingCancel", null, null, null, () => {});
cleanupRuntime.foreign("reentrant", "reentrantCancel", null, null, null, () => {});
cleanupRuntime.foreign("rejecting", "rejectingCancel", null, null, null, () => {});
const cleanupState = [false];
const cleanupBase = () => { cleanupBaseCalls += 1; };
cleanupBase.instrumentation = () => [];
cleanupBase.regionInstrumentation = () => [];
const cleanup = makeEffectDisposer(cleanupBase, cleanupState, 0, cleanupRuntime);
cleanup();
cleanup();
await drain();
const cleanupErrors = cleanup.effectErrors();
cleanupErrors.push({ code: "consumer", message: "mutation" });
if (!cleanupState[0] || cleanupBaseCalls !== 1 ||
    JSON.stringify(cleanup.effectInstrumentation()) !== "[3,3]" ||
    cleanup.effectErrors().length !== 2 ||
    cleanup.effectErrors().some((error) => error.code !== "LRX-PORT-403") ||
    unhandled.length !== 0) {
  throw new Error("effect cancellation was reentrant, mutable, or cleanup-unsafe");
}

process.off("unhandledRejection", captureUnhandled);

console.log("effect runtime contract passed");
