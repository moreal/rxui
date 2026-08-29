// detach, anchor, snapshot, placeInOrder, and rebuild are shared with
// leanrx_delta_region.mjs and leanrx_unkeyed_region.mjs; generated code imports
// createKeyedRegion plus, for ADR-0047 branch-cell replacement, detach.
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

// True when the keys of items (items[i][0]) are all numbers, all bigints, or
// all strings and strictly increasing or strictly decreasing; < totally orders
// each of those types, so such keys are pairwise distinct (across types it is
// not transitive: "10" < "5" < 6 < "10").
function monotoneKeys(items, count) {
  if (count === 0) return true;
  const type = typeof items[0][0];
  if (type !== "number" && type !== "bigint" && type !== "string") return false;
  let ascending = true;
  let descending = true;
  let previous = items[0][0];
  for (let index = 1; index < count; index += 1) {
    const key = items[index][0];
    if (typeof key !== type) return false;
    if (!(previous < key)) ascending = false;
    if (!(previous > key)) descending = false;
    if (!ascending && !descending) return false;
    previous = key;
  }
  return true;
}

// update(items, context) reconciles the whole target (items[i][0] is the key),
// forwarding context to the mount/update/dispose callbacks; updateAt(index,
// item, context) re-runs updateItem for one retained, key-checked position;
// swapAt(first, second, items, context) exchanges two retained positions with
// at most two moves and re-runs updateItem for them; insertAt(index, item,
// context) mounts one row into a position and shifts the rest, and
// removeAt(index, key, context) disposes one retained row and shifts the rest,
// and removeMany(drops, context) does the same for an ascending set of them in
// one pass, all without re-rendering anything else; setDisplayed(index, key,
// displayed) takes one retained row out of the parent or puts it back where
// its position says, without disposing it.
// A row taken out by setDisplayed is still in the row table, so the table's
// positions and the parent's children stop being the same list (ADR-0102).
// Every other entry point is written against that identity, so each restores
// it for itself: the anchors below are displayed anchors, and the reconcile
// puts the whole table back into the parent before it runs and takes the same
// rows out again after. A row is displayed exactly when its node is in the
// parent -- nothing here caches what the DOM already says -- and hiddenRows is
// only the O(1) test for whether any of that work is needed at all.
// The key index (entries) exists only after an update needed it (a retained
// key away from its position, or keys that are not monotone) and until an
// update retains nothing.
export function createKeyedRegion(parent, mountItem, updateItem, disposeItem, rootItem = null) {
  const marker = anchor(parent, "leanrx:keyed");
  const metrics = [0, 0, 0, 0]; // mounts/updates/moves/disposals
  let entries = null;
  let current = [];
  let stamp = 0;
  let disposed = false;
  let hiddenRows = 0;
  // The node a row that is not in the parent goes before once it is: after the
  // nearest displayed row ahead of it, and otherwise before the first
  // displayed row behind it, or before the marker. Backwards first because a
  // sweep walks the table upward, which makes that neighbour the row it just
  // placed -- so showing k rows costs one walk of the table, not k of them.
  function displayAnchor(index) {
    for (let ahead = index - 1; ahead >= 0; ahead -= 1) {
      const node = current[ahead].node;
      if (node.parentNode !== null) return node.nextSibling;
    }
    return insertAnchor(index + 1);
  }
  // The same node for a position no row holds yet: everything before index is
  // already in place, so only the first displayed row at or after it matters.
  function insertAnchor(index) {
    for (let behind = index; behind < current.length; behind += 1) {
      const node = current[behind].node;
      if (node.parentNode !== null) return node;
    }
    return marker;
  }
  // Puts every row setDisplayed took out back at its table position and
  // returns them, so a caller can undo it. One descending pass carries the
  // anchor, so it costs one walk of the table however many rows are out.
  function restoreDisplayed() {
    if (hiddenRows === 0) return [];
    const restored = [];
    let before = marker;
    for (let index = current.length - 1; index >= 0; index -= 1) {
      const entry = current[index];
      if (entry.node.parentNode === null) {
        parent.insertBefore(entry.node, before);
        restored.push(entry);
      }
      before = entry.node;
    }
    return restored;
  }
  return {
    update(items, context) {
      if (disposed) return;
      // ADR-0102: the reconcile's prefix and suffix scans, its
      // longest-increasing placement and its owned-parent bulk clear all read
      // the parent's children as the row table, so the rows a filter took out
      // go back first and the survivors among them come out again after. The
      // set is unchanged by the round trip, which is what a retained node
      // keeping its own display state means.
      const restored = restoreDisplayed();
      const count = items.length;
      const previous = current;
      const previousCount = previous.length;
      stamp += 1;
      // Validate every key before the first callback or DOM mutation: a key at
      // its previous position is retained outright; the first key elsewhere
      // (every earlier one was retained) decides whether the keys are monotone
      // (hence distinct, so a key is looked up only while a previous row is
      // still unmatched) or not (every key is looked up and a repeated one
      // drops the index and throws). The index is built from the previous rows
      // on first use and every new entry joins it while it exists.
      const next = new Array(count);
      let distinct = null;
      let retained = 0;
      for (let position = 0; position < count; position += 1) {
        const key = items[position][0];
        let entry;
        if (position < previousCount && previous[position].key === key) {
          entry = previous[position];
        } else {
          if (distinct === null) distinct = monotoneKeys(items, count);
          if (!distinct || retained < previousCount) {
            if (entries === null) {
              entries = new Map();
              for (const old of previous) entries.set(old.key, old);
            }
            entry = entries.get(key);
          }
        }
        if (entry === undefined) {
          entry = { key, handle: null, node: null, stamp, pos: -1 };
          if (entries !== null) entries.set(key, entry);
        } else if (entry.stamp === stamp) {
          entries = null;
          throw duplicateKey(key);
        } else {
          entry.stamp = stamp;
          retained += 1;
        }
        next[position] = entry;
      }
      if (retained === 0) entries = null;
      for (let position = 0; position < count; position += 1) {
        const entry = next[position];
        if (entry.node !== null) {
          updateItem(entry.handle, items[position], position, context);
        } else {
          const handle = mountItem(items[position], position, context);
          entry.handle = handle;
          entry.node = rootItem ? rootItem(handle) : handle;
        }
      }
      metrics[0] += count - retained;
      metrics[1] += retained;
      if (retained === 0) {
        for (let position = 0; position < previousCount; position += 1) {
          const entry = previous[position];
          disposeItem(entry.handle, entry.key, context);
        }
        metrics[3] += previousCount;
        metrics[2] += rebuild(parent, marker, previous, previousCount, next, count);
      } else {
        let kept = 0;
        for (let position = 0; position < previousCount; position += 1) {
          const entry = previous[position];
          if (entry.stamp === stamp) {
            previous[kept] = entry;
            kept += 1;
          } else {
            disposeItem(entry.handle, entry.key, context);
            detach(entry.node);
            if (entries !== null) entries.delete(entry.key);
            metrics[3] += 1;
          }
        }
        metrics[2] += placeInOrder(parent, marker, previous, kept, next, count);
      }
      current = next;
      if (restored.length !== 0) {
        hiddenRows = 0;
        for (let index = 0; index < restored.length; index += 1) {
          const entry = restored[index];
          if (entry.stamp === stamp) {
            hiddenRows += 1;
            detach(entry.node);
          }
        }
      }
    },
    updateAt(index, item, context) {
      if (disposed) return;
      const entry = current[index];
      if (entry === undefined || entry.key !== item[0]) throw mismatchedKey(index, item[0]);
      updateItem(entry.handle, item, index, context);
      metrics[1] += 1;
    },
    // items is the target order, which must differ from the current order only
    // by the exchange of first < second, so items[second][0] is checked at first
    // and items[first][0] at second before any callback or DOM mutation
    // (LRX-REGION-003 otherwise).
    swapAt(first, second, items, context) {
      if (disposed) return;
      const low = current[first];
      const high = current[second];
      const lowItem = items[first];
      const highItem = items[second];
      if (!(first < second) || low === undefined || high === undefined || low.key !== highItem[0]) {
        throw mismatchedKey(first, highItem?.[0]);
      }
      if (high.key !== lowItem[0]) throw mismatchedKey(second, lowItem[0]);
      current[first] = high;
      current[second] = low;
      if (hiddenRows === 0) {
        const adjacent = second === first + 1;
        const after = current[second + 1];
        parent.insertBefore(high.node, low.node);
        if (!adjacent) parent.insertBefore(low.node, after === undefined ? marker : after.node);
        metrics[2] += adjacent ? 1 : 2;
      } else {
        // Neither node is necessarily where its old position said, and one of
        // them may not be in the parent at all, so each displayed node is
        // taken out and placed at the anchor its new position names.
        const highShown = high.node.parentNode !== null;
        const lowShown = low.node.parentNode !== null;
        if (highShown) detach(high.node);
        if (lowShown) detach(low.node);
        if (highShown) {
          parent.insertBefore(high.node, displayAnchor(first));
          metrics[2] += 1;
        }
        if (lowShown) {
          parent.insertBefore(low.node, displayAnchor(second));
          metrics[2] += 1;
        }
      }
      updateItem(high.handle, lowItem, first, context);
      updateItem(low.handle, highItem, second, context);
      metrics[1] += 2;
    },
    // One row is mounted and placed at index — before the row that holds it
    // now, or before the marker at current.length, any other index being
    // LRX-REGION-003 — and every other row keeps its handle, its node and its
    // rendering. The caller owns key freshness exactly as it owns the items
    // array update reconciles; a key the index already holds is caught here
    // (LRX-REGION-001), and the index exists only when an update needed it.
    insertAt(index, item, context) {
      if (disposed) return;
      const key = item[0];
      if (!(Number.isInteger(index) && index >= 0 && index <= current.length)) {
        throw mismatchedKey(index, key);
      }
      if (entries !== null && entries.has(key)) {
        entries = null;
        throw duplicateKey(key);
      }
      const handle = mountItem(item, index, context);
      const entry = { key, handle, node: null, stamp, pos: -1 };
      entry.node = rootItem ? rootItem(handle) : handle;
      parent.insertBefore(entry.node, insertAnchor(index));
      current.splice(index, 0, entry);
      if (entries !== null) entries.set(key, entry);
      metrics[0] += 1;
      metrics[2] += 1;
    },
    // The retained row at index, whose key must be key (LRX-REGION-003
    // otherwise), is disposed and detached; later rows shift one position and
    // keep their handles and nodes without an update callback.
    removeAt(index, key, context) {
      if (disposed) return;
      const entry = current[index];
      if (entry === undefined || entry.key !== key) throw mismatchedKey(index, key);
      current.splice(index, 1);
      disposeItem(entry.handle, key, context);
      if (entry.node.parentNode === null) hiddenRows -= 1;
      detach(entry.node);
      if (entries !== null) entries.delete(key);
      metrics[3] += 1;
    },
    // The retained rows named by drops -- strictly ascending [position, key]
    // pairs against the order this call starts in, LRX-REGION-003 otherwise --
    // are disposed and detached, and the survivors close the gaps with one
    // native copy per surviving run. Every survivor keeps its handle, its node
    // and its rendering without an update callback, exactly as removeAt leaves
    // them; the caller owns the same order obligation removeAt gives it, once
    // for the whole set instead of once per row.
    removeMany(drops, context) {
      if (disposed) return;
      const count = drops.length;
      if (count === 0) return;
      const total = current.length;
      let last = -1;
      for (let index = 0; index < count; index += 1) {
        const position = drops[index][0];
        const entry = current[position];
        if (!(position > last) || entry === undefined || entry.key !== drops[index][1]) {
          throw mismatchedKey(position, drops[index][1]);
        }
        last = position;
      }
      // A removal that takes every row out of a parent the region owns clears
      // it in one write, which is the rebuild path's trick. It is one *call*
      // and not one cost: ADR-0103 measured `parent.textContent = ""` against
      // count removeChild calls at 0.974x on this repository's widest row and
      // 1.111x on a row that is one text node, because the browser charges
      // 368 ns per row plus 156 ns per node inside it either way. count is
      // nonzero here, so count === total implies the table is nonempty.
      const wholesale = count === total &&
        ownsWholeParent(parent, marker, current[0].node, total);
      for (let index = 0; index < count; index += 1) {
        const entry = current[drops[index][0]];
        disposeItem(entry.handle, entry.key, context);
        if (entry.node.parentNode === null) hiddenRows -= 1;
        if (!wholesale) detach(entry.node);
        if (entries !== null) entries.delete(entry.key);
      }
      if (wholesale) {
        parent.textContent = "";
        parent.appendChild(marker);
        current.length = 0;
      } else {
        let write = drops[0][0];
        for (let index = 0; index < count; index += 1) {
          const from = drops[index][0] + 1;
          const to = index + 1 < count ? drops[index + 1][0] : total;
          if (to > from) {
            current.copyWithin(write, from, to);
            write += to - from;
          }
        }
        current.length = write;
      }
      metrics[3] += count;
    },
    // The retained row at index, whose key must be key (LRX-REGION-003
    // otherwise), leaves the parent or goes back into it at the position the
    // row table gives it. It keeps its handle, its node, its listeners and
    // every property written into it either way, and no callback runs: this
    // is a filter's selection, not a change to the row. A row already in the
    // asked-for state is not touched, so the call is idempotent and the
    // caller's own displayed-state cache decides how often it is made.
    // Both directions are floors and ADR-0103 says so with the browser's own
    // numbers. Taking k rows out costs 368 ns each plus 156 ns per node in
    // the row, which no bulk call reduces because the nodes leave the
    // document either way; putting them back costs 1.045 us * N + 14.83 us * k
    // of style and layout, which is exactly what mounting k fresh rows into
    // the same places costs (0.975-1.016x, inside an A/A band of 0.958-1.009x)
    // -- a detached node carries neither a discount nor a penalty.
    setDisplayed(index, key, displayed) {
      if (disposed) return;
      const entry = current[index];
      if (entry === undefined || entry.key !== key) throw mismatchedKey(index, key);
      if ((entry.node.parentNode !== null) === displayed) return;
      if (displayed) {
        hiddenRows -= 1;
        parent.insertBefore(entry.node, displayAnchor(index));
      } else {
        hiddenRows += 1;
        detach(entry.node);
      }
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
      entries = null;
      current = [];
      hiddenRows = 0;
      detach(marker);
    },
  };
}
