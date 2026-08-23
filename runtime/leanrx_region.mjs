// detach, anchor, snapshot, placeInOrder, and rebuild are shared with
// leanrx_delta_region.mjs and leanrx_unkeyed_region.mjs; generated code imports
// only createKeyedRegion.
export function detach(node) {
  if (node.parentNode) node.parentNode.removeChild(node);
}

export function anchor(parent, label) {
  const marker = document.createComment(label);
  parent.append(marker);
  return marker;
}

export function snapshot(metrics) {
  return metrics.slice();
}

function duplicateKey(key) {
  return new Error(`LRX-REGION-001 duplicate key: ${String(key)}`);
}

// True when parent holds exactly the region's count nodes followed by marker.
function ownsWholeParent(parent, marker, first, count) {
  return parent.firstChild === first && marker.nextSibling === null &&
    parent.childNodes.length === count + 1;
}

// Flags one longest increasing subsequence of entries[start..end].pos (pos < 0
// skipped), scanning from the end so earlier positions stay in place on ties.
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

// Places next (target order) given old[0..oldCount) (retained, DOM order): inserts
// new nodes, moves only retained nodes outside one longest order-preserving
// subsequence, and returns the placement count. Entry.pos is -1 outside this call.
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

// Replaces previous[0..previousCount) (disposed, nothing retained) with
// next[0..newCount); a region that owns its whole parent clears it in bulk and,
// when connected, unfocused, and receiving rows, rebuilds it detached.
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

function mismatchedKey(index, key) {
  return new Error(`LRX-REGION-003 key ${String(key)} is not at position ${index}`);
}

// update(items, context) reconciles the whole target (items[i][0] is the key),
// forwarding context to the mount/update/dispose callbacks; updateAt(index,
// item, context) re-runs updateItem for one retained, key-checked position.
export function createKeyedRegion(parent, mountItem, updateItem, disposeItem, rootItem = null) {
  const marker = anchor(parent, "leanrx:keyed");
  const metrics = [0, 0, 0, 0]; // mounts/updates/moves/disposals
  const entries = new Map();
  let current = [];
  let stamp = 0;
  let disposed = false;
  return {
    update(items, context) {
      if (disposed) return;
      const count = items.length;
      const previous = current;
      const previousCount = previous.length;
      stamp += 1;
      // Validate every key (by position, then the index) before the first
      // callback or DOM mutation; a repeated key unregisters the new entries.
      const next = new Array(count);
      const empty = entries.size === 0;
      let retained = 0;
      for (let index = 0; index < count; index += 1) {
        const key = items[index][0];
        let entry = empty ? undefined
          : index < previousCount && previous[index].key === key ? previous[index]
          : entries.get(key);
        if (entry === undefined) {
          entry = { key, handle: null, node: null, stamp, pos: -1 };
          entries.set(key, entry);
          if (empty && entries.size !== index + 1) {
            entries.clear();
            throw duplicateKey(key);
          }
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
          updateItem(entry.handle, items[index], index, context);
        } else {
          const handle = mountItem(items[index], index, context);
          entry.handle = handle;
          entry.node = rootItem ? rootItem(handle) : handle;
        }
      }
      metrics[0] += count - retained;
      metrics[1] += retained;
      if (retained === 0) {
        for (let index = 0; index < previousCount; index += 1) {
          const entry = previous[index];
          disposeItem(entry.handle, entry.key, context);
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
            disposeItem(entry.handle, entry.key, context);
            detach(entry.node);
            entries.delete(entry.key);
            metrics[3] += 1;
          }
        }
        metrics[2] += placeInOrder(parent, marker, previous, kept, next, count);
      }
      current = next;
    },
    updateAt(index, item, context) {
      if (disposed) return;
      const entry = current[index];
      if (entry === undefined || entry.key !== item[0]) throw mismatchedKey(index, item[0]);
      updateItem(entry.handle, item, index, context);
      metrics[1] += 1;
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
