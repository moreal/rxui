/** Detaches `node` from its parent when it has one. Shared with
 * leanrx_delta_region.mjs; not a generated-code entry point. */
export function detach(node) {
  if (node.parentNode) node.parentNode.removeChild(node);
}

/** Appends and returns a region's comment marker. Shared with
 * leanrx_delta_region.mjs; not a generated-code entry point. */
export function anchor(parent, label) {
  const marker = document.createComment(label);
  parent.append(marker);
  return marker;
}

/** Copies a region's counters. Shared with leanrx_delta_region.mjs; not a
 * generated-code entry point. */
export function snapshot(metrics) {
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

/** Places next (target order) given old[0..oldCount) (retained entries in DOM
 * order, all present in next). Inserts new nodes and moves only retained nodes
 * outside one longest order-preserving subsequence; returns the placement count.
 * Entries carry a scratch `pos` that is -1 outside this call. Shared with
 * leanrx_delta_region.mjs; not a generated-code entry point. */
export function placeInOrder(parent, marker, old, oldCount, next, newCount) {
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

/** Replaces every node of previous[0..previousCount) (already disposed) with
 * next[0..newCount) when no entry is retained; returns the placement count.
 * A region that owns its whole parent (its first node through its marker, no
 * foreign sibling) removes the old rows with one bulk clear and, while the
 * parent is connected, not focused, and about to receive rows, detaches that
 * parent so the browser attaches the rebuilt subtree once instead of per row.
 * Shared with leanrx_delta_region.mjs; not a generated-code entry point. */
export function rebuild(parent, marker, previous, previousCount, next, newCount) {
  const first = previousCount > 0 ? previous[0].node : marker;
  if (!ownsWholeParent(parent, marker, first, previousCount)) {
    for (let index = 0; index < previousCount; index += 1) detach(previous[index].node);
    return placeInOrder(parent, marker, previous, 0, next, newCount);
  }
  const container = newCount > 0 && document.activeElement !== parent ? parent.parentNode : null;
  const sibling = container ? parent.nextSibling : null;
  if (container) container.removeChild(parent);
  if (previousCount > 0) {
    parent.textContent = "";
    parent.appendChild(marker);
  }
  const placements = placeInOrder(parent, marker, previous, 0, next, newCount);
  if (container) container.insertBefore(parent, sibling);
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
      const previous = current;
      const previousCount = previous.length;
      stamp += 1;
      // Validate the whole target before the first callback or DOM mutation. A
      // retained key is matched by position first (no hashing while the order is
      // unchanged), then through the key index; a new key registers an unmounted
      // entry; a repeated key unregisters the new entries and fails.
      const next = new Array(count);
      let retained = 0;
      for (let index = 0; index < count; index += 1) {
        const key = items[index][0];
        let entry = index < previousCount && previous[index].key === key
          ? previous[index]
          : entries.get(key);
        if (entry === undefined) {
          entry = { key, handle: null, node: null, stamp, pos: -1 };
          entries.set(key, entry);
        } else if (entry.stamp === stamp) {
          for (let added = 0; added < index; added += 1) {
            if (next[added].node === null) entries.delete(next[added].key);
          }
          throw duplicateKey(key);
        } else {
          entry.stamp = stamp;
          retained += 1;
        }
        next[index] = entry;
      }
      for (let index = 0; index < count; index += 1) {
        const entry = next[index];
        if (entry.node !== null) {
          updateItem(entry.handle, items[index], index);
          metrics[1] += 1;
        } else {
          const handle = mountItem(items[index], index);
          entry.handle = handle;
          entry.node = rootItem ? rootItem(handle) : handle;
          metrics[0] += 1;
        }
      }
      if (retained === 0) {
        for (let index = 0; index < previousCount; index += 1) {
          const entry = previous[index];
          disposeItem(entry.handle, entry.key);
          if (count > 0) entries.delete(entry.key);
        }
        if (count === 0) entries.clear();
        metrics[3] += previousCount;
        metrics[2] += rebuild(parent, marker, previous, previousCount, next, count);
      } else {
        let kept = 0;
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
        metrics[2] += placeInOrder(parent, marker, previous, kept, next, count);
      }
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
