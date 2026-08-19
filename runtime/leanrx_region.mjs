function detach(node) {
  if (node.parentNode) node.parentNode.removeChild(node);
}

function anchor(parent, label) {
  const marker = document.createComment(label);
  parent.append(marker);
  return marker;
}

function snapshot(metrics) {
  return metrics.slice();
}

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

export function createKeyedRegion(parent, mountItem, updateItem, disposeItem) {
  const marker = anchor(parent, "leanrx:keyed");
  const metrics = [0, 0, 0, 0]; // mounts/updates/moves/disposals
  let entries = new Map();
  let disposed = false;
  return {
    update(items) {
      if (disposed) return;
      const seen = new Set();
      for (const item of items) {
        const key = item[0];
        if (seen.has(key)) throw new Error(`LRX-REGION-001 duplicate key: ${String(key)}`);
        seen.add(key);
      }
      const next = new Map();
      const order = [];
      for (let index = 0; index < items.length; index += 1) {
        const item = items[index];
        const key = item[0];
        let entry = entries.get(key);
        if (entry) {
          updateItem(entry.node, item, index);
          metrics[1] += 1;
        } else {
          entry = { node: mountItem(item, index) };
          metrics[0] += 1;
        }
        next.set(key, entry);
        order.push(entry.node);
      }
      for (const [key, entry] of entries) {
        if (!next.has(key)) {
          disposeItem(entry.node, key);
          detach(entry.node);
          metrics[3] += 1;
        }
      }
      let cursor = marker;
      for (let index = order.length - 1; index >= 0; index -= 1) {
        const node = order[index];
        if (node.nextSibling !== cursor) {
          parent.insertBefore(node, cursor);
          metrics[2] += 1;
        }
        cursor = node;
      }
      entries = next;
    },
    instrumentation() {
      return snapshot(metrics);
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      for (const [key, entry] of entries) {
        disposeItem(entry.node, key);
        detach(entry.node);
        metrics[3] += 1;
      }
      entries.clear();
      detach(marker);
    },
  };
}
