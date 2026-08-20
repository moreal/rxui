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

  function begin(handle, cancel) {
    if (disposed) return false;
    cancelHandle(handle);
    owned.set(handle, cancel);
    metrics[8] += 1;
    return true;
  }

  function finish(handle, deliver, result) {
    if (disposed || !owned.has(handle)) return;
    owned.delete(handle);
    deliver(result);
  }

  function cancelHandle(handle) {
    const cancel = owned.get(handle);
    if (!cancel) return false;
    owned.delete(handle);
    cancel();
    metrics[9] += 1;
    return true;
  }

  function timeout(handle, delayMs, deliver) {
    let timer = null;
    if (!begin(handle, () => clearTimer(timer))) return;
    timer = setTimer(() => finish(handle, deliver, { ok: true, value: null }), delayMs);
  }

  function storageGet(handle, key, deliver) {
    if (!begin(handle, () => {})) return;
    Promise.resolve()
      .then(() => storage.getItem(key))
      .then((value) => finish(handle, deliver, {
        ok: true,
        value: value === null ? { kind: "missing" } : { kind: "found", value },
      }))
      .catch((error) => finish(handle, deliver, {
        ok: false,
        error: effectError("LRX-STORAGE-001", error),
      }));
  }

  function storageSet(handle, key, value, deliver) {
    if (!begin(handle, () => {})) return;
    Promise.resolve()
      .then(() => storage.setItem(key, value))
      .then(() => finish(handle, deliver, { ok: true, value: null }))
      .catch((error) => finish(handle, deliver, {
        ok: false,
        error: effectError("LRX-STORAGE-002", error),
      }));
  }

  function http(handle, request, deliver) {
    const controller = new AbortController();
    if (!begin(handle, () => controller.abort())) return;
    Promise.resolve()
      .then(() => fetchImpl(queryUrl(request), {
        method: request.method ?? "GET",
        signal: controller.signal,
      }))
      .then(async (response) => ({ status: response.status, body: await response.text() }))
      .then((value) => finish(handle, deliver, { ok: true, value }))
      .catch((error) => {
        if (error?.name === "AbortError") return;
        finish(handle, deliver, { ok: false, error: effectError("LRX-HTTP-001", error) });
      });
  }

  function foreign(handle, name, input, deliver) {
    const port = ports[name];
    if (!port || typeof port.run !== "function") {
      if (!begin(handle, () => {})) return;
      finish(handle, deliver, {
        ok: false,
        error: effectError("LRX-PORT-004", `foreign port ${JSON.stringify(name)} is unavailable`),
      });
      return;
    }
    let cancel = () => {};
    if (!begin(handle, () => cancel())) return;
    let operation;
    try {
      operation = port.run(input);
      if (operation && typeof operation === "object" && "promise" in operation) {
        cancel = typeof operation.cancel === "function" ? operation.cancel : () => {};
        operation = operation.promise;
      }
    } catch (error) {
      finish(handle, deliver, { ok: false, error: effectError("LRX-PORT-005", error) });
      return;
    }
    Promise.resolve(operation)
      .then((value) => finish(handle, deliver, { ok: true, value }))
      .catch((error) => finish(handle, deliver, {
        ok: false,
        error: effectError("LRX-PORT-005", error),
      }));
  }

  function dispose() {
    if (disposed) return;
    disposed = true;
    for (const cancel of owned.values()) {
      cancel();
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
