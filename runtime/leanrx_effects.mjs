function effectError(code, cause) {
  let message = "unprintable effect failure";
  try {
    if (cause && typeof cause === "object" && typeof cause.message === "string") {
      message = cause.message;
    } else {
      message = String(cause);
    }
  } catch {
    // Hostile rejection values may throw from property access or string conversion.
  }
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
  const onError = typeof adapters.onError === "function" ? adapters.onError : null;
  const errors = [];
  let disposed = false;

  function report(code, cause) {
    const error = effectError(code, cause);
    errors.push(error);
    if (onError) {
      try {
        onError({ ...error });
      } catch {
        // Effect cleanup and normalization never delegate failure to user code.
      }
    }
  }

  function invokeCancel(entry) {
    try {
      Promise.resolve(entry.cancel()).catch((error) => report("LRX-PORT-403", error));
    } catch (error) {
      report("LRX-PORT-403", error);
    }
  }

  function begin(handle, cancel, state, context, deliver) {
    if (disposed) return null;
    cancelHandle(handle);
    const entry = { cancel, state, context, deliver };
    owned.set(handle, entry);
    metrics[8] += 1;
    return entry;
  }

  function finish(handle, entry, deliver, result) {
    if (disposed || owned.get(handle) !== entry) return;
    owned.delete(handle);
    try {
      (deliver ?? entry.deliver)(entry.state, entry.context, handle, result);
    } catch (error) {
      report("LRX-PORT-901", error);
    }
  }

  function cancelHandle(handle) {
    const entry = owned.get(handle);
    if (!entry) return false;
    owned.delete(handle);
    metrics[9] += 1;
    invokeCancel(entry);
    return true;
  }

  function timeout(handle, delayMs, state, context, deliver) {
    let timer = null;
    const entry = begin(handle, () => clearTimer(timer), state, context, deliver);
    if (!entry) return;
    try {
      timer = setTimer(() => finish(handle, entry, null, { ok: true, value: null }), delayMs);
    } catch (error) {
      if (owned.get(handle) === entry) owned.delete(handle);
      report("LRX-PORT-203", error);
    }
  }

  function storageGet(handle, key, state, context, deliver) {
    const entry = begin(handle, () => {}, state, context, deliver);
    if (!entry) return;
    Promise.resolve()
      .then(() => storage.getItem(key))
      .then((value) => finish(handle, entry, null, {
        ok: true,
        value: value === null ? { kind: "missing" } : { kind: "found", value },
      }))
      .catch((error) => finish(handle, entry, null, {
        ok: false,
        error: effectError("LRX-PORT-201", error),
      }));
  }

  function storageSet(handle, key, value, state, context, deliver) {
    const entry = begin(handle, () => {}, state, context, deliver);
    if (!entry) return;
    Promise.resolve()
      .then(() => storage.setItem(key, value))
      .then(() => finish(handle, entry, null, { ok: true, value: null }))
      .catch((error) => finish(handle, entry, null, {
        ok: false,
        error: effectError("LRX-PORT-202", error),
      }));
  }

  function http(handle, method, url, query, decoder, state, context, deliver) {
    const controller = new AbortController();
    const entry = begin(handle, () => controller.abort(), state, context, deliver);
    if (!entry) return;
    Promise.resolve()
      .then(() => fetchImpl(queryUrl({ url, query }), {
        method,
        signal: controller.signal,
      }))
      .then(async (response) => ({ status: response.status, body: await response.text() }))
      .then((value) => decoder ? decoder(value) : { ok: true, value })
      .then((result) => finish(handle, entry, null, result))
      .catch((error) => {
        let aborted = false;
        try {
          aborted = error?.name === "AbortError";
        } catch {
          // A hostile rejection object is normalized below.
        }
        if (aborted) return;
        finish(handle, entry, null, {
          ok: false,
          error: effectError("LRX-PORT-301", error),
        });
      });
  }

  function foreign(handle, name, input, state, context, deliver) {
    const port = ports[name];
    if (!port || typeof port.run !== "function") {
      const entry = begin(handle, () => {}, state, context, deliver);
      if (!entry) return;
      finish(handle, entry, null, {
        ok: false,
        error: effectError("LRX-PORT-401", `foreign port ${JSON.stringify(name)} is unavailable`),
      });
      return;
    }
    let cancel = () => {};
    const entry = begin(handle, () => cancel(), state, context, deliver);
    if (!entry) return;
    let operation;
    try {
      operation = port.run(input);
      if (operation && typeof operation === "object" && "promise" in operation) {
        cancel = typeof operation.cancel === "function" ? operation.cancel : () => {};
        operation = operation.promise;
      }
    } catch (error) {
      finish(handle, entry, null, {
        ok: false,
        error: effectError("LRX-PORT-402", error),
      });
      return;
    }
    Promise.resolve(operation)
      .then((value) => finish(handle, entry, null, { ok: true, value }))
      .catch((error) => finish(handle, entry, null, {
        ok: false,
        error: effectError("LRX-PORT-402", error),
      }));
  }

  function dispose() {
    if (disposed) return;
    disposed = true;
    const entries = [...owned.values()];
    owned.clear();
    metrics[9] += entries.length;
    for (const entry of entries) invokeCancel(entry);
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
    errors: () => errors.map((error) => ({ ...error })),
  };
}

export function makeEffectDisposer(baseDisposer, state, disposedIndex, effects) {
  let disposed = false;
  function dispose() {
    if (disposed) return;
    disposed = true;
    state[disposedIndex] = true;
    try {
      effects.dispose();
    } finally {
      baseDisposer();
    }
  }
  dispose.instrumentation = baseDisposer.instrumentation;
  dispose.regionInstrumentation = baseDisposer.regionInstrumentation;
  dispose.effectInstrumentation = effects.instrumentation;
  dispose.effectErrors = effects.errors;
  return dispose;
}
