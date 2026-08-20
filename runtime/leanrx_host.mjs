export function makeDisposer(root, listenerDisposers, metrics, regions = [], gridWork = null) {
  let disposed = false;
  function dispose() {
    if (disposed) return;
    disposed = true;
    let firstError = null;
    for (const removeListener of listenerDisposers.splice(0)) {
      try {
        removeListener();
      } catch (error) {
        firstError ??= error;
      }
    }
    try {
      root.remove();
    } catch (error) {
      firstError ??= error;
    }
    if (firstError) throw firstError;
  }
  dispose.instrumentation = () => [
    metrics[0], metrics[1], metrics[2], metrics[3], metrics[4], metrics[5],
    metrics[6], metrics[7].slice(), metrics[8], metrics[9],
  ];
  dispose.regionInstrumentation = () => regions.map((region) => region.instrumentation());
  dispose.gridInstrumentation = () => gridWork?.slice() ?? [];
  return dispose;
}
