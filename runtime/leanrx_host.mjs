export function makeDisposer(root, listenerDisposers) {
  let disposed = false;
  return function dispose() {
    if (disposed) return;
    disposed = true;
    for (const removeListener of listenerDisposers) removeListener();
    root.remove();
  };
}
