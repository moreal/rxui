export function makeDisposer(root, listenerDisposers, metrics, regions = []) {
  let disposed = false;
  function dispose() {
    if (disposed) return;
    disposed = true;
    for (const removeListener of listenerDisposers) removeListener();
    root.remove();
  }
  dispose.instrumentation = () => [
    metrics[0], metrics[1], metrics[2], metrics[3], metrics[4], metrics[5],
    metrics[6], metrics[7].slice(), metrics[8], metrics[9],
  ];
  dispose.regionInstrumentation = () => regions.map((region) => region.instrumentation());
  return dispose;
}
