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

function duplicateKey(key) {
  return new Error(`LRX-REGION-001 duplicate key: ${String(key)}`);
}

// True when parent holds exactly the region's `count` nodes followed by marker.
function ownsWholeParent(parent, marker, first, count) {
  return parent.firstChild === first && marker.nextSibling === null &&
    parent.childNodes.length === count + 1;
}

// Flags one longest increasing subsequence of entries[start..end].pos (pos < 0
// skipped). The scan runs from the end so that, among equally long choices,
// earlier target positions stay in place (a two-row reversal keeps the first).
function markLongestIncreasing(entries, start, end, flags) {
  const length = end - start + 1;
  const tails = new Int32Array(length);
  const previous = new Int32Array(length);
  let size = 0;
  for (let offset = length - 1; offset >= 0; offset -= 1) {
    const position = entries[start + offset].pos;
    if (position < 0) continue;
    let low = 0;
    let high = size;
    while (low < high) {
      const middle = (low + high) >> 1;
      if (entries[start + tails[middle]].pos > position) low = middle + 1;
      else high = middle;
    }
    previous[offset] = low > 0 ? tails[low - 1] : -1;
    tails[low] = offset;
    if (low === size) size += 1;
  }
  let offset = size > 0 ? tails[size - 1] : -1;
  while (offset >= 0) {
    flags[offset] = 1;
    offset = previous[offset];
  }
}

// Places next (target order) given old[0..oldCount) (retained entries in DOM
// order, all present in next). Inserts new nodes and moves only retained nodes
// outside one longest order-preserving subsequence; returns the placement count.
// Entries carry a scratch `pos` that is -1 outside this call.
function placeInOrder(parent, marker, old, oldCount, next, newCount) {
  let start = 0;
  while (start < oldCount && start < newCount && old[start] === next[start]) start += 1;
  let oldEnd = oldCount - 1;
  let newEnd = newCount - 1;
  while (oldEnd >= start && newEnd >= start && old[oldEnd] === next[newEnd]) {
    oldEnd -= 1;
    newEnd -= 1;
  }
  if (start > newEnd) return 0;
  const after = newEnd + 1 < newCount ? next[newEnd + 1].node : marker;
  if (start > oldEnd) {
    for (let index = start; index <= newEnd; index += 1) {
      parent.insertBefore(next[index].node, after);
    }
    return newEnd - start + 1;
  }
  for (let index = start; index <= oldEnd; index += 1) old[index].pos = index;
  const stable = new Uint8Array(newEnd - start + 1);
  markLongestIncreasing(next, start, newEnd, stable);
  let placements = 0;
  let before = after;
  for (let index = newEnd; index >= start; index -= 1) {
    const entry = next[index];
    if (entry.pos < 0 || stable[index - start] === 0) {
      parent.insertBefore(entry.node, before);
      placements += 1;
    }
    before = entry.node;
  }
  for (let index = start; index <= oldEnd; index += 1) old[index].pos = -1;
  return placements;
}

export function createKeyedRegion(parent, mountItem, updateItem, disposeItem, rootItem = null) {
  const marker = anchor(parent, "leanrx:keyed");
  const metrics = [0, 0, 0, 0]; // mounts/updates/moves/disposals
  const entries = new Map();
  let current = [];
  let stamp = 0;
  let disposed = false;
  return {
    update(items) {
      if (disposed) return;
      const count = items.length;
      stamp += 1;
      // Validate the whole target before the first callback or DOM mutation.
      const next = new Array(count);
      let retained = 0;
      let fresh = null;
      for (let index = 0; index < count; index += 1) {
        const key = items[index][0];
        const entry = entries.get(key);
        if (entry !== undefined) {
          if (entry.stamp === stamp) throw duplicateKey(key);
          entry.stamp = stamp;
          retained += 1;
        } else if (fresh === null) {
          fresh = new Set([key]);
        } else if (fresh.has(key)) {
          throw duplicateKey(key);
        } else {
          fresh.add(key);
        }
        next[index] = entry === undefined ? null : entry;
      }
      const previous = current;
      const previousCount = previous.length;
      const replaced = retained === 0 && previousCount > 0;
      if (replaced) entries.clear();
      for (let index = 0; index < count; index += 1) {
        const item = items[index];
        let entry = next[index];
        if (entry !== null) {
          updateItem(entry.handle, item, index);
          metrics[1] += 1;
        } else {
          const handle = mountItem(item, index);
          entry = { key: item[0], handle, node: rootItem ? rootItem(handle) : handle, stamp, pos: -1 };
          entries.set(entry.key, entry);
          next[index] = entry;
          metrics[0] += 1;
        }
      }
      let kept = 0;
      if (replaced) {
        for (let index = 0; index < previousCount; index += 1) {
          const entry = previous[index];
          disposeItem(entry.handle, entry.key);
        }
        if (ownsWholeParent(parent, marker, previous[0].node, previousCount)) {
          parent.textContent = "";
          parent.appendChild(marker);
        } else {
          for (let index = 0; index < previousCount; index += 1) detach(previous[index].node);
        }
        metrics[3] += previousCount;
      } else {
        for (let index = 0; index < previousCount; index += 1) {
          const entry = previous[index];
          if (entry.stamp === stamp) {
            previous[kept] = entry;
            kept += 1;
          } else {
            disposeItem(entry.handle, entry.key);
            detach(entry.node);
            entries.delete(entry.key);
            metrics[3] += 1;
          }
        }
      }
      metrics[2] += placeInOrder(parent, marker, previous, kept, next, count);
      current = next;
    },
    instrumentation() {
      return snapshot(metrics);
    },
    dispose() {
      if (disposed) return;
      disposed = true;
      for (let index = 0; index < current.length; index += 1) {
        const entry = current[index];
        disposeItem(entry.handle, entry.key);
        detach(entry.node);
        metrics[3] += 1;
      }
      entries.clear();
      current = [];
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
        entry = { key, handle, node: rootItem ? rootItem(handle) : handle, pos: -1 };
        metrics[0] += 1;
      }
      next.push(entry);
    }
    let kept = 0;
    for (let index = 0; index < entries.length; index += 1) {
      const entry = entries[index];
      if (oldByKey.has(entry.key)) {
        disposeItem(entry.handle, entry.key);
        detach(entry.node);
        metrics[3] += 1;
      } else {
        entries[kept] = entry;
        kept += 1;
      }
    }
    metrics[2] += placeInOrder(parent, marker, entries, kept, next, next.length);
    entries = next;
    metrics[4] += 1;
  }

  function applyOne(delta) {
    const tag = delta[0];
    if (tag === "insert") {
      const index = delta[1];
      const item = delta[2];
      const handle = mountItem(item, index);
      const entry = { key: item[0], handle, node: rootItem ? rootItem(handle) : handle, pos: -1 };
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
