import { createKeyedRegion } from "../../runtime/leanrx_region.mjs";
import {
  createConditionalRegion,
  createPositionalRegion,
} from "../../runtime/leanrx_unkeyed_region.mjs";
import { createDeltaKeyedRegion } from "../../runtime/leanrx_delta_region.mjs";
import { makeDisposer } from "../../runtime/leanrx_dom.mjs";

class FakeNode {
  constructor(value) {
    this.value = value;
    this.parentNode = null;
    this.disposals = 0;
  }

  get nextSibling() {
    if (!this.parentNode) return null;
    const index = this.parentNode.children.indexOf(this);
    return this.parentNode.children[index + 1] ?? null;
  }
}

class FakeParent extends FakeNode {
  constructor() {
    super("parent");
    this.children = [];
  }

  append(node) {
    this.insertBefore(node, null);
  }

  insertBefore(node, before) {
    if (node.parentNode) node.parentNode.removeChild(node);
    const index = before === null ? this.children.length : this.children.indexOf(before);
    if (index < 0) throw new Error("missing insertion anchor");
    this.children.splice(index, 0, node);
    node.parentNode = this;
  }

  removeChild(node) {
    const index = this.children.indexOf(node);
    if (index < 0) throw new Error("missing removal node");
    this.children.splice(index, 1);
    node.parentNode = null;
    this.removals = (this.removals ?? 0) + 1;
  }

  appendChild(node) {
    this.insertBefore(node, null);
  }

  get firstChild() {
    return this.children[0] ?? null;
  }

  get childNodes() {
    return this.children;
  }

  set textContent(value) {
    if (value !== "") throw new Error("fake parent only supports clearing");
    for (const node of this.children) node.parentNode = null;
    this.children = [];
    this.bulkClears = (this.bulkClears ?? 0) + 1;
  }
}

globalThis.document = {
  createComment(label) {
    return new FakeNode(label);
  },
};

function values(parent) {
  return parent.children.filter((node) => !node.value.startsWith("leanrx:"))
    .map((node) => node.value);
}

{
  const listeners = [];
  const calls = [];
  listeners.push(() => { calls.push("first"); throw new Error("listener failed"); });
  listeners.push(() => calls.push("second"));
  const root = { remove() { calls.push("root"); } };
  const metrics = [0, 1, 2, 3, 4, 5, 6, ["trace"], 8, 9];
  const gridWork = [10, 20, 30];
  const dispose = makeDisposer(root, listeners, metrics, [], gridWork);
  let failed = false;
  try {
    dispose();
  } catch (error) {
    failed = String(error).includes("listener failed");
  }
  if (!failed || JSON.stringify(calls) !== '["first","second","root"]' || listeners.length !== 0) {
    throw new Error("host disposal did not clear retained listener closures after complete cleanup");
  }
  const snapshot = dispose.gridInstrumentation();
  snapshot[0] = 999;
  if (dispose.gridInstrumentation()[0] !== 10) throw new Error("grid work snapshot is mutable");
  dispose();
  if (calls.length !== 3) throw new Error("host disposal lost idempotence after cleanup failure");
}

{
  const parent = new FakeParent();
  const region = createConditionalRegion(
    parent,
    (branch, value) => new FakeNode(`${branch}:${value}`),
    (node, branch, value) => { node.value = `${branch}:${value}`; },
    (node) => { node.disposals += 1; },
  );
  region.update(true, "a");
  const first = parent.children[0];
  region.update(true, "b");
  if (parent.children[0] !== first || values(parent)[0] !== "true:b") {
    throw new Error("conditional region replaced a stable branch");
  }
  region.update(false, "c");
  if (first.disposals !== 1 || values(parent)[0] !== "false:c") {
    throw new Error("conditional region failed branch disposal");
  }
  region.dispose();
  region.dispose();
  if (parent.children.length !== 0 || JSON.stringify(region.instrumentation()) !== "[2,1,2]") {
    throw new Error("conditional region disposal/instrumentation changed");
  }
}

{
  const parent = new FakeParent();
  const region = createPositionalRegion(
    parent,
    (item) => new FakeNode(item),
    (node, item) => { node.value = item; },
    (node) => { node.disposals += 1; },
  );
  region.update(["a", "b"]);
  const first = parent.children[0];
  region.update(["A", "b", "c"]);
  if (parent.children[0] !== first || JSON.stringify(values(parent)) !== '["A","b","c"]') {
    throw new Error("positional region lost prefix identity");
  }
  const removed = parent.children[2];
  region.update(["A"]);
  if (removed.disposals !== 1 || JSON.stringify(values(parent)) !== '["A"]') {
    throw new Error("positional region failed suffix disposal");
  }
  region.dispose();
  if (parent.children.length !== 0 || JSON.stringify(region.instrumentation()) !== "[3,3,3]") {
    throw new Error("positional region instrumentation changed");
  }
}

{
  const parent = new FakeParent();
  const region = createKeyedRegion(
    parent,
    (item) => [new FakeNode(`${item[0]}:${item[1]}`)],
    (handle, item) => { handle[0].value = `${item[0]}:${item[1]}`; },
    (handle) => { handle[0].disposals += 1; },
    (handle) => handle[0],
  );
  region.update([[1, "a"], [2, "b"], [3, "c"]]);
  const identities = new Map(parent.children.slice(0, 3).map((node) => [node.value[0], node]));
  region.update([[3, "c"], [1, "a"], [2, "B"]]);
  const reordered = parent.children.slice(0, 3);
  if (reordered[0] !== identities.get("3") || reordered[1] !== identities.get("1") ||
      reordered[2] !== identities.get("2") || reordered[2].value !== "2:B") {
    throw new Error("keyed region lost identity across reorder");
  }
  const beforeDuplicate = values(parent);
  let duplicateFailed = false;
  try {
    region.update([[1, "a"], [1, "duplicate"]]);
  } catch (error) {
    duplicateFailed = String(error).includes("LRX-REGION-001");
  }
  if (!duplicateFailed || JSON.stringify(values(parent)) !== JSON.stringify(beforeDuplicate)) {
    throw new Error("duplicate keyed update mutated the region");
  }
  const removed = identities.get("1");
  region.update([[3, "c"], [2, "B"], [4, "d"]]);
  if (removed.disposals !== 1 || JSON.stringify(values(parent)) !== '["3:c","2:B","4:d"]') {
    throw new Error("keyed region failed removal/insertion");
  }
  const copy = region.instrumentation();
  copy[0] = 999;
  if (region.instrumentation()[0] !== 4) throw new Error("region instrumentation is mutable");
  region.dispose();
  if (parent.children.length !== 0) throw new Error("keyed region disposal leaked nodes");
}

{
  const parent = new FakeParent();
  const region = createDeltaKeyedRegion(
    parent,
    (item) => [new FakeNode(`${item[0]}:${item[1]}`)],
    (handle, item) => { handle[0].value = `${item[0]}:${item[1]}`; },
    (handle) => { handle[0].disposals += 1; },
    (handle) => handle[0],
  );
  region.update([[1, "a"], [2, "b"], [3, "c"], [4, "d"]]);
  const identities = new Map(parent.children.slice(0, 4).map((node) => [node.value[0], node]));
  region.apply([["update", 2, [3, "C"]]]);
  if (parent.children[2] !== identities.get("3") || values(parent)[2] !== "3:C") {
    throw new Error("delta update lost keyed identity");
  }
  region.apply([["move", 3, 0], ["remove", 2], ["insert", 1, [5, "e"]]]);
  if (parent.children[0] !== identities.get("4") ||
      JSON.stringify(values(parent)) !== '["4:d","5:e","1:a","3:C"]') {
    throw new Error("delta move/remove/insert produced the wrong order");
  }
  const beforeInvalid = values(parent);
  let invalidFailed = false;
  try {
    region.apply([["remove", 0], ["update", 9, [3, "bad"]]]);
  } catch (error) {
    invalidFailed = String(error).includes("LRX-DELTA-003");
  }
  if (!invalidFailed || JSON.stringify(values(parent)) !== JSON.stringify(beforeInvalid)) {
    throw new Error("invalid delta batch mutated before validation completed");
  }
  function expectDeltaFailure(batch, code) {
    const before = JSON.stringify(values(parent));
    let failed = false;
    try {
      region.apply(batch);
    } catch (error) {
      failed = String(error).includes(code);
    }
    if (!failed || JSON.stringify(values(parent)) !== before) {
      throw new Error(`${code} delta validator branch mutated or accepted its batch`);
    }
  }
  expectDeltaFailure([["insert", 9, [8, "bad"]]], "LRX-DELTA-001");
  expectDeltaFailure([["insert", 0, [4, "duplicate"]]], "LRX-REGION-001");
  expectDeltaFailure([["remove", -1]], "LRX-DELTA-002");
  expectDeltaFailure([["move", 9, 0]], "LRX-DELTA-004");
  expectDeltaFailure([["move", 0, 9]], "LRX-DELTA-005");
  expectDeltaFailure({}, "LRX-DELTA-006");
  expectDeltaFailure([[]], "LRX-DELTA-006");
  expectDeltaFailure([["insert", 0, []]], "LRX-DELTA-006");
  expectDeltaFailure([["reset", {}]], "LRX-DELTA-006");
  expectDeltaFailure([["reset", [[]]]], "LRX-DELTA-006");
  expectDeltaFailure([["reset", [[8, "a"], [8, "b"]]]], "LRX-REGION-001");
  expectDeltaFailure([["unknown"]], "LRX-DELTA-006");
  let keyChangeFailed = false;
  try {
    region.apply([["update", 0, [99, "bad"]]]);
  } catch (error) {
    keyChangeFailed = String(error).includes("LRX-DELTA-007");
  }
  if (!keyChangeFailed || JSON.stringify(values(parent)) !== JSON.stringify(beforeInvalid)) {
    throw new Error("delta update allowed a key change");
  }
  const retained = parent.children[0];
  region.apply([["reset", [[4, "D"], [6, "f"]]]]);
  if (parent.children[0] !== retained || JSON.stringify(values(parent)) !== '["4:D","6:f"]') {
    throw new Error("delta reset lost retained keyed identity");
  }
  const metrics = region.instrumentation();
  metrics[5] = 999;
  if (region.instrumentation()[5] !== 5) throw new Error("delta metrics are mutable");
  region.dispose();
  region.dispose();
  region.apply([["insert", 0, [7, "ignored"]]]);
  if (parent.children.length !== 0) throw new Error("delta region disposal leaked nodes");
}

{
  const parent = new FakeParent();
  const region = createDeltaKeyedRegion(
    parent,
    (item) => [new FakeNode(`${item[0]}:${item[1]}`)],
    (handle, item) => { handle[0].value = `${item[0]}:${item[1]}`; },
    () => {},
    (handle) => handle[0],
  );
  region.update([[1, "a"], [2, "b"], [3, "c"], [4, "d"]]);
  const first = parent.children[0];
  const last = parent.children[3];
  region.apply([["move", 3, 0], ["move", 1, 3]]);
  if (JSON.stringify(values(parent)) !== '["4:d","2:b","3:c","1:a"]' ||
      parent.children[0] !== last || parent.children[3] !== first) {
    throw new Error("two-move swap batch lost its order or keyed identity");
  }
  region.dispose();
}

{
  // Keyed placement cost: a swap moves two nodes, a rotation moves one, appends
  // and prepends place only the new nodes, and pure updates place nothing.
  const parent = new FakeParent();
  const region = createKeyedRegion(
    parent,
    (item) => [new FakeNode(`${item[0]}`)],
    (handle, item) => { handle[0].value = `${item[0]}`; },
    () => {},
    (handle) => handle[0],
  );
  const rows = (keys) => keys.map((key) => [key, "x"]);
  const moves = () => region.instrumentation()[2];
  region.update(rows([1, 2, 3, 4, 5, 6, 7, 8]));
  if (moves() !== 8) throw new Error(`initial placement count ${moves()}`);
  const nodes = parent.children.slice(0, 8);
  region.update(rows([1, 7, 3, 4, 5, 6, 2, 8]));
  if (moves() !== 10 || JSON.stringify(values(parent)) !== '["1","7","3","4","5","6","2","8"]' ||
      parent.children[1] !== nodes[6] || parent.children[6] !== nodes[1]) {
    throw new Error(`keyed swap did not cost exactly two placements (${moves()})`);
  }
  region.update(rows([8, 1, 7, 3, 4, 5, 6, 2]));
  if (moves() !== 11 || JSON.stringify(values(parent)) !== '["8","1","7","3","4","5","6","2"]' ||
      parent.children[0] !== nodes[7]) {
    throw new Error(`keyed rotation did not move exactly the rotated node (${moves()})`);
  }
  region.update(rows([8, 1, 7, 3, 4, 5, 6, 2]));
  if (moves() !== 11) throw new Error("unchanged keyed order placed nodes");
  region.update(rows([8, 1, 7, 3, 4, 5, 6, 2, 9, 10]));
  if (moves() !== 13 || parent.children[7] !== nodes[1]) {
    throw new Error(`keyed append placed retained nodes (${moves()})`);
  }
  region.update(rows([0, 8, 1, 7, 3, 4, 5, 6, 2, 9, 10]));
  if (moves() !== 14) throw new Error(`keyed prepend placed retained nodes (${moves()})`);
  region.update(rows([0, 8, 1, 7, 3, 5, 6, 2, 9, 10]));
  if (moves() !== 14 || JSON.stringify(values(parent)) !== '["0","8","1","7","3","5","6","2","9","10"]') {
    throw new Error("keyed removal placed nodes");
  }
  region.update(rows([0, 8, 1, 7, 3, 11, 5, 6, 2, 9, 10]));
  if (moves() !== 15 || parent.children[5].value !== "11") {
    throw new Error("keyed middle insertion placed retained nodes");
  }
  if (JSON.stringify(region.instrumentation()) !== "[12,62,15,1]") {
    throw new Error(`keyed placement metrics changed: ${JSON.stringify(region.instrumentation())}`);
  }
  region.dispose();
}

{
  // Reversing two rows keeps the first target row (and any focus inside it) in
  // place and moves only the second; larger reversals move all but one row.
  const parent = new FakeParent();
  const region = createKeyedRegion(
    parent,
    (item) => [new FakeNode(`${item[0]}`)],
    () => {},
    () => {},
    (handle) => handle[0],
  );
  region.update([[1, "a"], [2, "b"]]);
  const [first, second] = parent.children;
  region.update([[2, "b"], [1, "a"]]);
  const movesAfterSwap = region.instrumentation()[2];
  if (movesAfterSwap !== 3 || parent.children[0] !== second || parent.children[1] !== first) {
    throw new Error("two-row reversal moved the first target row");
  }
  region.update([[2, "b"], [1, "a"], [3, "c"], [4, "d"]]);
  region.update([[4, "d"], [3, "c"], [1, "a"], [2, "b"]]);
  if (region.instrumentation()[2] !== movesAfterSwap + 2 + 3 ||
      JSON.stringify(values(parent)) !== '["4","3","1","2"]') {
    throw new Error("four-row reversal did not cost three placements");
  }
  region.dispose();
}

{
  // Clearing or replacing every row of a region that owns its whole parent uses
  // one bulk removal; the marker and disposal accounting are retained.
  const parent = new FakeParent();
  let disposals = 0;
  const region = createKeyedRegion(
    parent,
    (item) => [new FakeNode(`${item[0]}`)],
    () => {},
    () => { disposals += 1; },
    (handle) => handle[0],
  );
  region.update([[1, "a"], [2, "b"], [3, "c"]]);
  region.update([]);
  if (parent.bulkClears !== 1 || disposals !== 3 || parent.children.length !== 1 ||
      parent.children[0].value !== "leanrx:keyed") {
    throw new Error("keyed clear did not bulk-remove an owned parent");
  }
  region.update([[4, "d"], [5, "e"]]);
  const retained = parent.children[0];
  region.update([[6, "f"], [7, "g"]]);
  if (parent.bulkClears !== 2 || disposals !== 5 || retained.parentNode !== null ||
      JSON.stringify(values(parent)) !== '["6","7"]') {
    throw new Error("keyed replace-all did not bulk-remove an owned parent");
  }
  const foreign = new FakeNode("foreign");
  parent.insertBefore(foreign, parent.children[0]);
  region.update([]);
  if (parent.bulkClears !== 2 || disposals !== 7 || JSON.stringify(values(parent)) !== '["foreign"]') {
    throw new Error("keyed clear bulk-removed a parent it does not own");
  }
  if (JSON.stringify(region.instrumentation()) !== "[7,0,7,7]") {
    throw new Error(`bulk clear metrics changed: ${JSON.stringify(region.instrumentation())}`);
  }
  region.dispose();
  if (parent.children.length !== 1 || parent.children[0] !== foreign) {
    throw new Error("keyed disposal after bulk clear leaked nodes");
  }
}

{
  // An empty region rejects a repeated key before mounting anything and stays
  // usable; the same holds after a clear.
  const parent = new FakeParent();
  let mounts = 0;
  const region = createKeyedRegion(
    parent,
    (item) => { mounts += 1; return [new FakeNode(`${item[0]}`)]; },
    () => {},
    () => {},
    (handle) => handle[0],
  );
  for (const round of [0, 1]) {
    let failed = false;
    try {
      region.update([[1, "a"], [2, "b"], [1, "again"]]);
    } catch (error) {
      failed = String(error).includes("LRX-REGION-001") && String(error).includes("1");
    }
    if (!failed || mounts !== 2 * round || parent.children.length !== 1) {
      throw new Error(`empty region accepted or mounted a repeated key (round ${round})`);
    }
    region.update([[1, "a"], [2, "b"]]);
    if (mounts !== 2 * (round + 1) || JSON.stringify(values(parent)) !== '["1","2"]') {
      throw new Error(`empty region did not recover after a repeated key (round ${round})`);
    }
    region.update([]);
  }
  region.dispose();
}

{
  // Deterministic fuzz: arbitrary keyed targets always yield the target order
  // with retained identity, never place more nodes than a full rebuild would,
  // and reject duplicates before mutating.
  let seed = 0x2f6e2b1;
  const random = (bound) => {
    seed = (Math.imul(seed, 1103515245) + 12345) >>> 0;
    return seed % bound;
  };
  const parent = new FakeParent();
  const identity = new Map();
  let disposals = 0;
  const region = createKeyedRegion(
    parent,
    (item) => {
      const node = new FakeNode(`${item[0]}`);
      identity.set(item[0], node);
      return [node];
    },
    (handle, item) => { handle[0].value = `${item[0]}`; },
    (handle, key) => { disposals += 1; identity.delete(key); },
    (handle) => handle[0],
  );
  let previousMoves = 0;
  for (let round = 0; round < 400; round += 1) {
    const size = random(40);
    const keys = [];
    const used = new Set();
    while (keys.length < size) {
      const key = random(60);
      if (!used.has(key)) { used.add(key); keys.push(key); }
    }
    const before = JSON.stringify(values(parent));
    const retainedNodes = keys.filter((key) => identity.has(key)).map((key) => [key, identity.get(key)]);
    if (round % 7 === 3 && keys.length > 0) {
      let failed = false;
      try {
        region.update([...keys, keys[0]].map((key) => [key, "dup"]));
      } catch (error) {
        failed = String(error).includes("LRX-REGION-001");
      }
      if (!failed || JSON.stringify(values(parent)) !== before) {
        throw new Error("fuzz duplicate update mutated the keyed region");
      }
    }
    region.update(keys.map((key) => [key, "v"]));
    if (JSON.stringify(values(parent)) !== JSON.stringify(keys.map(String))) {
      throw new Error(`fuzz round ${round} produced the wrong order`);
    }
    for (const [key, node] of retainedNodes) {
      if (identity.get(key) !== node || node.parentNode !== parent) {
        throw new Error(`fuzz round ${round} lost identity for key ${key}`);
      }
    }
    const moves = region.instrumentation()[2];
    if (moves - previousMoves > keys.length) {
      throw new Error(`fuzz round ${round} placed more nodes than a rebuild`);
    }
    previousMoves = moves;
    if (identity.size !== keys.length || parent.children.length !== keys.length + 1) {
      throw new Error(`fuzz round ${round} leaked or lost nodes`);
    }
  }
  region.dispose();
  if (parent.children.length !== 0 || identity.size !== 0 || disposals === 0) {
    throw new Error("fuzzed keyed region disposal leaked nodes");
  }
}

{
  // The structural-delta region's full reconcile shares the same placement bound.
  const parent = new FakeParent();
  const region = createDeltaKeyedRegion(
    parent,
    (item) => [new FakeNode(`${item[0]}`)],
    () => {},
    () => {},
    (handle) => handle[0],
  );
  const rows = (keys) => keys.map((key) => [key, "x"]);
  region.update(rows([1, 2, 3, 4, 5, 6]));
  const nodes = parent.children.slice(0, 6);
  region.update(rows([1, 5, 3, 4, 2, 6]));
  if (region.instrumentation()[2] !== 8 || parent.children[1] !== nodes[4] ||
      parent.children[4] !== nodes[1] ||
      JSON.stringify(values(parent)) !== '["1","5","3","4","2","6"]') {
    throw new Error("delta region full reconcile swap did not cost two placements");
  }
  region.apply([["reset", rows([6, 1, 5, 3, 4, 2])]]);
  if (region.instrumentation()[2] !== 9 || JSON.stringify(values(parent)) !== '["6","1","5","3","4","2"]') {
    throw new Error("delta region reset rotation did not cost one placement");
  }
  region.dispose();
}

{
  // Rebuilding a region that owns its whole connected parent detaches that
  // parent for the bulk clear and insertion, then restores it at the same
  // position; an unowned or focused parent, a pure clear, and a retained row
  // leave the parent attached throughout.
  const grandparent = new FakeParent();
  const before = new FakeNode("before");
  const parent = new FakeParent();
  const after = new FakeNode("after");
  grandparent.append(before);
  grandparent.append(parent);
  grandparent.append(after);
  const region = createKeyedRegion(
    grandparent.children[1],
    (item) => [new FakeNode(`${item[0]}`)],
    (handle, item) => { handle[0].value = `${item[0]}`; },
    () => {},
    (handle) => handle[0],
  );
  const rows = (keys) => keys.map((key) => [key, "x"]);
  const attachedAt = (index) => grandparent.children[index] === parent && parent.parentNode === grandparent;
  region.update(rows([1, 2, 3]));
  if (grandparent.removals !== 1 || !attachedAt(1) || grandparent.children.length !== 3 ||
      JSON.stringify(values(parent)) !== '["1","2","3"]') {
    throw new Error("first fill of an owned connected parent did not detach and restore it once");
  }
  region.update(rows([4, 5]));
  if (grandparent.removals !== 2 || parent.bulkClears !== 1 || !attachedAt(1) ||
      JSON.stringify(values(parent)) !== '["4","5"]') {
    throw new Error("replace-all of an owned connected parent did not detach and restore it once");
  }
  region.update(rows([4, 6]));
  if (grandparent.removals !== 2 || !attachedAt(1) || JSON.stringify(values(parent)) !== '["4","6"]') {
    throw new Error("an update with a retained row detached the parent");
  }
  region.update([]);
  if (grandparent.removals !== 2 || parent.bulkClears !== 2 || !attachedAt(1)) {
    throw new Error("a pure clear detached the parent");
  }
  globalThis.document.activeElement = parent;
  region.update(rows([7]));
  if (grandparent.removals !== 2 || !attachedAt(1) || JSON.stringify(values(parent)) !== '["7"]') {
    throw new Error("a focused parent was detached");
  }
  globalThis.document.activeElement = null;
  const foreign = new FakeNode("foreign");
  parent.insertBefore(foreign, parent.children[0]);
  region.update(rows([8, 9]));
  if (grandparent.removals !== 2 || parent.bulkClears !== 2 || !attachedAt(1) ||
      JSON.stringify(values(parent)) !== '["foreign","8","9"]') {
    throw new Error("an unowned parent was detached or bulk-cleared");
  }
  if (JSON.stringify(region.instrumentation()) !== "[9,1,9,7]") {
    throw new Error(`rebuild metrics changed: ${JSON.stringify(region.instrumentation())}`);
  }
  region.dispose();
  if (parent.children.length !== 1 || parent.children[0] !== foreign || !attachedAt(1)) {
    throw new Error("disposal after rebuilds leaked nodes or moved the parent");
  }
}

{
  // The structural-delta region's full reconcile shares the owned-parent rebuild.
  const grandparent = new FakeParent();
  const parent = new FakeParent();
  grandparent.append(parent);
  const region = createDeltaKeyedRegion(
    parent,
    (item) => [new FakeNode(`${item[0]}`)],
    () => {},
    () => {},
    (handle) => handle[0],
  );
  region.update([[1, "a"], [2, "b"]]);
  region.apply([["reset", [[3, "c"]]]]);
  if (grandparent.removals !== 2 || parent.bulkClears !== 1 || parent.parentNode !== grandparent ||
      JSON.stringify(values(parent)) !== '["3"]' ||
      JSON.stringify(region.instrumentation()) !== "[3,0,3,2,2,1,4]") {
    throw new Error(`delta rebuild changed: ${JSON.stringify(region.instrumentation())}`);
  }
  region.dispose();
}

{
  // Both keyed regions forward the per-update context unchanged to the mount,
  // update, and dispose callbacks; older callers that pass none see undefined.
  for (const create of [createKeyedRegion, createDeltaKeyedRegion]) {
    const parent = new FakeParent();
    const seen = [];
    const region = create(
      parent,
      (item, index, context) => { seen.push(["mount", item[0], index, context]); return [new FakeNode(`${item[0]}`)]; },
      (handle, item, index, context) => { seen.push(["update", item[0], index, context]); },
      (handle, key, context) => { seen.push(["dispose", key, context]); },
      (handle) => handle[0],
    );
    const first = { tag: "first" };
    const second = { tag: "second" };
    region.update([[1, "a"], [2, "b"]], first);
    region.update([[2, "b"]], second);
    region.update([[2, "b"], [3, "c"]]);
    if (JSON.stringify(seen) !== JSON.stringify([
      ["mount", 1, 0, first], ["mount", 2, 1, first],
      ["update", 2, 0, second], ["dispose", 1, second],
      ["update", 2, 0, undefined], ["mount", 3, 1, undefined],
    ])) {
      throw new Error(`${create.name} did not forward the update context: ${JSON.stringify(seen)}`);
    }
    region.dispose();
  }
}

{
  // updateAt re-runs the update callback for one retained position with the
  // forwarded context and counts one update; it refuses a key that is not at
  // that position or a position outside the region before calling anything,
  // and is a no-op after disposal.
  const parent = new FakeParent();
  const calls = [];
  const region = createKeyedRegion(
    parent,
    (item) => [new FakeNode(`${item[0]}:${item[1]}`)],
    (handle, item, index, context) => {
      calls.push([item[0], index, context]);
      handle[0].value = `${item[0]}:${item[1]}`;
    },
    () => {},
    (handle) => handle[0],
  );
  region.update([[1, "a"], [2, "b"], [3, "c"]]);
  const nodes = parent.children.slice(0, 3);
  const context = { tag: "select" };
  region.updateAt(1, [2, "B"], context);
  if (JSON.stringify(values(parent)) !== '["1:a","2:B","3:c"]' || parent.children[1] !== nodes[1] ||
      JSON.stringify(calls) !== '[[2,1,{"tag":"select"}]]' ||
      JSON.stringify(region.instrumentation()) !== "[3,1,3,0]") {
    throw new Error(`updateAt did not update exactly one retained row: ${JSON.stringify(calls)}`);
  }
  function expectMismatch(index, item) {
    let failed = false;
    try {
      region.updateAt(index, item, context);
    } catch (error) {
      failed = String(error).includes("LRX-REGION-003");
    }
    if (!failed || calls.length !== 1 || JSON.stringify(values(parent)) !== '["1:a","2:B","3:c"]') {
      throw new Error(`updateAt accepted key ${item[0]} at position ${index}`);
    }
  }
  expectMismatch(0, [2, "wrong"]);
  expectMismatch(3, [4, "outside"]);
  expectMismatch(-1, [1, "negative"]);
  region.update([[3, "c"], [1, "a"]]);
  region.updateAt(1, [1, "A"], context);
  if (JSON.stringify(values(parent)) !== '["3:c","1:A"]' || calls.length !== 4 ||
      JSON.stringify(region.instrumentation()) !== "[3,4,4,1]") {
    throw new Error("updateAt after a reorder did not address the current order");
  }
  region.dispose();
  region.updateAt(0, [3, "ignored"], context);
  if (calls.length !== 4 || parent.children.length !== 0) {
    throw new Error("updateAt ran after disposal");
  }
}

{
  // An empty region registers each new key with one index insertion; the
  // repeated key may be far from its first occurrence and nothing is mounted.
  const parent = new FakeParent();
  let mounts = 0;
  const region = createKeyedRegion(
    parent,
    (item) => { mounts += 1; return [new FakeNode(`${item[0]}`)]; },
    () => {},
    () => {},
    (handle) => handle[0],
  );
  let failed = false;
  try {
    region.update([[1, "a"], [2, "b"], [3, "c"], [4, "d"], [2, "again"]]);
  } catch (error) {
    failed = String(error).includes("LRX-REGION-001") && String(error).includes("2");
  }
  if (!failed || mounts !== 0 || parent.children.length !== 1) {
    throw new Error("empty region accepted a distant repeated key");
  }
  region.update([[4, "d"], [3, "c"]]);
  region.update([[3, "c"], [4, "d"], [5, "e"]]);
  if (mounts !== 3 || JSON.stringify(values(parent)) !== '["3","4","5"]' ||
      JSON.stringify(region.instrumentation()) !== "[3,2,4,0]") {
    throw new Error(`empty region recovery changed: ${JSON.stringify(region.instrumentation())}`);
  }
  region.dispose();
}

console.log("dynamic region runtime contract passed");
