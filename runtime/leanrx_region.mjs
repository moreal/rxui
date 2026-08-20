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

export function createKeyedRegion(parent, mountItem, updateItem, disposeItem, rootItem = null) {
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
          updateItem(entry.handle, item, index);
          metrics[1] += 1;
        } else {
          const handle = mountItem(item, index);
          entry = { handle, node: rootItem ? rootItem(handle) : handle };
          metrics[0] += 1;
        }
        next.set(key, entry);
        order.push(entry.node);
      }
      for (const [key, entry] of entries) {
        if (!next.has(key)) {
          disposeItem(entry.handle, key);
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
        disposeItem(entry.handle, key);
        detach(entry.node);
        metrics[3] += 1;
      }
      entries.clear();
      detach(marker);
    },
  };
}

function deltaError(code, message) {
  throw new Error(`${code} ${message}`);
}

function validateUniqueItems(items) {
  const seen = new Set();
  for (const item of items) {
    if (!Array.isArray(item) || item.length === 0) {
      deltaError("LRX-DELTA-006", "delta item must carry a key");
    }
    if (seen.has(item[0])) deltaError("LRX-REGION-001", `duplicate key: ${String(item[0])}`);
    seen.add(item[0]);
  }
  return Array.from(seen);
}

function validateDeltaBatch(currentKeys, deltas) {
  if (!Array.isArray(deltas)) deltaError("LRX-DELTA-006", "delta batch must be an array");
  const keys = currentKeys.slice();
  for (const delta of deltas) {
    if (!Array.isArray(delta) || typeof delta[0] !== "string") {
      deltaError("LRX-DELTA-006", "delta must be a tagged array");
    }
    const tag = delta[0];
    if (tag === "insert") {
      const index = delta[1];
      const item = delta[2];
      if (!Number.isSafeInteger(index) || index < 0 || index > keys.length) {
        deltaError("LRX-DELTA-001", `insert index ${String(index)} is invalid`);
      }
      if (!Array.isArray(item) || item.length === 0) {
        deltaError("LRX-DELTA-006", "inserted item must carry a key");
      }
      if (keys.includes(item[0])) {
        deltaError("LRX-REGION-001", `duplicate key: ${String(item[0])}`);
      }
      keys.splice(index, 0, item[0]);
    } else if (tag === "remove") {
      const index = delta[1];
      if (!Number.isSafeInteger(index) || index < 0 || index >= keys.length) {
        deltaError("LRX-DELTA-002", `remove index ${String(index)} is invalid`);
      }
      keys.splice(index, 1);
    } else if (tag === "update") {
      const index = delta[1];
      const item = delta[2];
      if (!Number.isSafeInteger(index) || index < 0 || index >= keys.length) {
        deltaError("LRX-DELTA-003", `update index ${String(index)} is invalid`);
      }
      if (!Array.isArray(item) || item.length === 0 || item[0] !== keys[index]) {
        deltaError("LRX-DELTA-007", "updated item must retain its key");
      }
    } else if (tag === "move") {
      const fromIndex = delta[1];
      const toIndex = delta[2];
      if (!Number.isSafeInteger(fromIndex) || fromIndex < 0 || fromIndex >= keys.length) {
        deltaError("LRX-DELTA-004", `move source ${String(fromIndex)} is invalid`);
      }
      if (!Number.isSafeInteger(toIndex) || toIndex < 0 || toIndex >= keys.length) {
        deltaError("LRX-DELTA-005", `move target ${String(toIndex)} is invalid`);
      }
      const [key] = keys.splice(fromIndex, 1);
      keys.splice(toIndex, 0, key);
    } else if (tag === "reset") {
      const items = delta[1];
      if (!Array.isArray(items)) deltaError("LRX-DELTA-006", "reset payload must be an array");
      keys.splice(0, keys.length, ...validateUniqueItems(items));
    } else {
      deltaError("LRX-DELTA-006", `unknown delta tag: ${tag}`);
    }
  }
}

/** A local keyed-region variant that consumes compiler-produced structural
 * edits. It owns only its anchor, keyed instances, and disposal; it does not
 * discover dependencies or schedule reactive work. Every batch is validated
 * completely before the first DOM mutation. */
export function createDeltaKeyedRegion(
  parent, mountItem, updateItem, disposeItem, rootItem = null,
) {
  const marker = anchor(parent, "leanrx:delta-keyed");
  const metrics = [0, 0, 0, 0, 0, 0, 0];
  // mounts/updates/moves/disposals/fullResets/deltaOps/acceptedValidationUnits
  let entries = [];
  let disposed = false;

  function reconcile(items, alreadyValidated = false) {
    if (!alreadyValidated) validateUniqueItems(items);
    metrics[6] += items.length;
    const oldByKey = new Map(entries.map((entry) => [entry.key, entry]));
    const next = [];
    for (let index = 0; index < items.length; index += 1) {
      const item = items[index];
      const key = item[0];
      let entry = oldByKey.get(key);
      if (entry) {
        updateItem(entry.handle, item, index);
        metrics[1] += 1;
        oldByKey.delete(key);
      } else {
        const handle = mountItem(item, index);
        entry = { key, handle, node: rootItem ? rootItem(handle) : handle };
        metrics[0] += 1;
      }
      next.push(entry);
    }
    for (const entry of oldByKey.values()) {
      disposeItem(entry.handle, entry.key);
      detach(entry.node);
      metrics[3] += 1;
    }
    let cursor = marker;
    for (let index = next.length - 1; index >= 0; index -= 1) {
      const node = next[index].node;
      if (node.nextSibling !== cursor) {
        parent.insertBefore(node, cursor);
        metrics[2] += 1;
      }
      cursor = node;
    }
    entries = next;
    metrics[4] += 1;
  }

  function applyOne(delta) {
    const tag = delta[0];
    if (tag === "insert") {
      const index = delta[1];
      const item = delta[2];
      const handle = mountItem(item, index);
      const entry = { key: item[0], handle, node: rootItem ? rootItem(handle) : handle };
      const before = entries[index]?.node ?? marker;
      parent.insertBefore(entry.node, before);
      entries.splice(index, 0, entry);
      metrics[0] += 1;
    } else if (tag === "remove") {
      const index = delta[1];
      const [entry] = entries.splice(index, 1);
      disposeItem(entry.handle, entry.key);
      detach(entry.node);
      metrics[3] += 1;
    } else if (tag === "update") {
      const index = delta[1];
      updateItem(entries[index].handle, delta[2], index);
      metrics[1] += 1;
    } else if (tag === "move") {
      const fromIndex = delta[1];
      const toIndex = delta[2];
      if (fromIndex !== toIndex) {
        const [entry] = entries.splice(fromIndex, 1);
        entries.splice(toIndex, 0, entry);
        const before = entries[toIndex + 1]?.node ?? marker;
        parent.insertBefore(entry.node, before);
        metrics[2] += 1;
      }
    } else {
      reconcile(delta[1], true);
    }
    metrics[5] += 1;
  }

  return {
    update(items) {
      if (disposed) return;
      reconcile(items);
    },
    apply(deltas) {
      if (disposed) return;
      validateDeltaBatch(entries.map((entry) => entry.key), deltas);
      metrics[6] += deltas.length;
      for (const delta of deltas) applyOne(delta);
    },
    instrumentation() {
      return snapshot(metrics);
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      for (const entry of entries) {
        disposeItem(entry.handle, entry.key);
        detach(entry.node);
        metrics[3] += 1;
      }
      entries = [];
      detach(marker);
    },
  };
}
