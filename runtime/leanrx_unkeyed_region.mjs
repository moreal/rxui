import { anchor, detach, snapshot } from "./leanrx_region.mjs";

/** The conditional (one mounted branch) and positional (index identity)
 * regions; shipped only by artifacts that import them. Like the keyed host
 * they are local reconcilers: they never discover dependencies or schedule
 * reactive work. */
export function createConditionalRegion(parent, mountBranch, updateBranch, disposeBranch) {
  const marker = anchor(parent, "leanrx:conditional");
  const metrics = [0, 0, 0]; // mounts/updates/disposals
  let current = null;
  let disposed = false;
  return {
    update(branch, payload) {
      if (disposed) return;
      if (current && current.branch === branch) {
        updateBranch(current.node, branch, payload);
        metrics[1] += 1;
        return;
      }
      if (current) {
        disposeBranch(current.node, current.branch);
        detach(current.node);
        metrics[2] += 1;
      }
      const node = mountBranch(branch, payload);
      parent.insertBefore(node, marker);
      current = { branch, node };
      metrics[0] += 1;
    },
    instrumentation() {
      return snapshot(metrics);
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      if (current) {
        disposeBranch(current.node, current.branch);
        detach(current.node);
        metrics[2] += 1;
        current = null;
      }
      detach(marker);
    },
  };
}

export function createPositionalRegion(parent, mountItem, updateItem, disposeItem) {
  const marker = anchor(parent, "leanrx:positional");
  const metrics = [0, 0, 0]; // mounts/updates/disposals
  let entries = [];
  let disposed = false;
  return {
    update(items) {
      if (disposed) return;
      const common = Math.min(entries.length, items.length);
      for (let index = 0; index < common; index += 1) {
        updateItem(entries[index], items[index], index);
        metrics[1] += 1;
      }
      for (let index = common; index < items.length; index += 1) {
        const node = mountItem(items[index], index);
        parent.insertBefore(node, marker);
        entries.push(node);
        metrics[0] += 1;
      }
      while (entries.length > items.length) {
        const node = entries.pop();
        disposeItem(node);
        detach(node);
        metrics[2] += 1;
      }
    },
    instrumentation() {
      return snapshot(metrics);
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      for (const node of entries) {
        disposeItem(node);
        detach(node);
        metrics[2] += 1;
      }
      entries = [];
      detach(marker);
    },
  };
}
