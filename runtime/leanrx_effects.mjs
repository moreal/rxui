function effectError(code, cause) {
  const message = cause instanceof Error ? cause.message : String(cause);
  return { code, message };
}

function queryUrl(request) {
  const url = new URL(request.url, "http://leanrx.invalid");
  for (const [name, value] of request.query ?? []) url.searchParams.append(name, value);
  return request.url.startsWith("http://") || request.url.startsWith("https://")
    ? url.toString()
    : `${url.pathname}${url.search}`;
}

export function createEffectRuntime(metrics, adapters = {}) {
  const owned = new Map();
  const storage = adapters.storage ?? globalThis.localStorage;
  const fetchImpl = adapters.fetch ?? globalThis.fetch;
  const ports = adapters.ports ?? {};
  const setTimer = adapters.setTimeout ?? globalThis.setTimeout;
  const clearTimer = adapters.clearTimeout ?? globalThis.clearTimeout;
  let disposed = false;

  function begin(handle, cancel, state, context, deliver) {
    if (disposed) return false;
    cancelHandle(handle);
    owned.set(handle, { cancel, state, context, deliver });
    metrics[8] += 1;
    return true;
  }

  function finish(handle, deliver, result) {
    if (disposed || !owned.has(handle)) return;
    const entry = owned.get(handle);
    owned.delete(handle);
    (deliver ?? entry.deliver)(entry.state, entry.context, handle, result);
  }

  function cancelHandle(handle) {
    const entry = owned.get(handle);
    if (!entry) return false;
    owned.delete(handle);
    entry.cancel();
    metrics[9] += 1;
    return true;
  }

  function timeout(handle, delayMs, state, context, deliver) {
    let timer = null;
    if (!begin(handle, () => clearTimer(timer), state, context, deliver)) return;
    timer = setTimer(() => finish(handle, null, { ok: true, value: null }), delayMs);
  }

  function storageGet(handle, key, state, context, deliver) {
    if (!begin(handle, () => {}, state, context, deliver)) return;
    Promise.resolve()
      .then(() => storage.getItem(key))
      .then((value) => finish(handle, null, {
        ok: true,
        value: value === null ? { kind: "missing" } : { kind: "found", value },
      }))
      .catch((error) => finish(handle, null, {
        ok: false,
        error: effectError("LRX-STORAGE-001", error),
      }));
  }

  function storageSet(handle, key, value, state, context, deliver) {
    if (!begin(handle, () => {}, state, context, deliver)) return;
    Promise.resolve()
      .then(() => storage.setItem(key, value))
      .then(() => finish(handle, null, { ok: true, value: null }))
      .catch((error) => finish(handle, null, {
        ok: false,
        error: effectError("LRX-STORAGE-002", error),
      }));
  }

  function http(handle, request, state, context, deliver) {
    const controller = new AbortController();
    if (!begin(handle, () => controller.abort(), state, context, deliver)) return;
    Promise.resolve()
      .then(() => fetchImpl(queryUrl(request), {
        method: request.method ?? "GET",
        signal: controller.signal,
      }))
      .then(async (response) => ({ status: response.status, body: await response.text() }))
      .then((value) => finish(handle, null, { ok: true, value }))
      .catch((error) => {
        if (error?.name === "AbortError") return;
        finish(handle, null, { ok: false, error: effectError("LRX-HTTP-001", error) });
      });
  }

  function foreign(handle, name, input, state, context, deliver) {
    const port = ports[name];
    if (!port || typeof port.run !== "function") {
      if (!begin(handle, () => {}, state, context, deliver)) return;
      finish(handle, null, {
        ok: false,
        error: effectError("LRX-PORT-004", `foreign port ${JSON.stringify(name)} is unavailable`),
      });
      return;
    }
    let cancel = () => {};
    if (!begin(handle, () => cancel(), state, context, deliver)) return;
    let operation;
    try {
      operation = port.run(input);
      if (operation && typeof operation === "object" && "promise" in operation) {
        cancel = typeof operation.cancel === "function" ? operation.cancel : () => {};
        operation = operation.promise;
      }
    } catch (error) {
      finish(handle, null, { ok: false, error: effectError("LRX-PORT-005", error) });
      return;
    }
    Promise.resolve(operation)
      .then((value) => finish(handle, null, { ok: true, value }))
      .catch((error) => finish(handle, null, {
        ok: false,
        error: effectError("LRX-PORT-005", error),
      }));
  }

  function dispose() {
    if (disposed) return;
    disposed = true;
    for (const entry of owned.values()) {
      entry.cancel();
      metrics[9] += 1;
    }
    owned.clear();
  }

  return {
    timeout,
    storageGet,
    storageSet,
    http,
    foreign,
    cancel: cancelHandle,
    dispose,
    instrumentation: () => [metrics[8], metrics[9]],
  };
}

export function makeEffectDisposer(baseDisposer, state, disposedIndex, effects) {
  let disposed = false;
  function dispose() {
    if (disposed) return;
    disposed = true;
    state[disposedIndex] = true;
    effects.dispose();
    baseDisposer();
  }
  dispose.instrumentation = baseDisposer.instrumentation;
  dispose.regionInstrumentation = baseDisposer.regionInstrumentation;
  dispose.effectInstrumentation = effects.instrumentation;
  return dispose;
}
