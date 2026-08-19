import {
  createConditionalRegion,
  createKeyedRegion,
  createPositionalRegion,
} from "../../runtime/leanrx_region.mjs";

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
    (item) => new FakeNode(`${item[0]}:${item[1]}`),
    (node, item) => { node.value = `${item[0]}:${item[1]}`; },
    (node) => { node.disposals += 1; },
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

console.log("dynamic region runtime contract passed");
