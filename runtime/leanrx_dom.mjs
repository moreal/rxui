export function createElement(tag) {
  return document.createElement(tag);
}

export function createText(data) {
  return document.createTextNode(data);
}

export function setAttribute(node, name, value) {
  node.setAttribute(name, value);
}

export function append(parent, child) {
  parent.appendChild(child);
}

export function childAt(parent, index) {
  return parent.childNodes[index];
}

export function firstChild(node) {
  return node.firstChild;
}

export function nextSibling(node) {
  return node.nextSibling;
}

/** Deep-clones a static prototype subtree that generated code built once. */
export function cloneTemplate(template) {
  return template.cloneNode(true);
}

/** Marks `node` as a delegated-event key carrier. `listenDelegated` resolves
 * the nearest ancestor-or-self key from this property or a `data-lrx-key`
 * attribute, so a keyed row root serves every action node inside it. */
export function setKey(node, key) {
  node.$lrxKey = key;
}

export function setText(node, value) {
  node.data = value;
}

export function setProperty(node, name, value) {
  node[name] = value;
}

let nextIdValue = 0;

export function uniqueId(prefix) {
  nextIdValue += 1;
  return `${prefix}-${nextIdValue}`;
}

// The key of the nearest ancestor-or-self of `actionNode` (up to `root`) that
// carries a `setKey` value or a `data-lrx-key` attribute; "" when none does.
function delegatedKey(actionNode, root) {
  for (let current = actionNode; current !== null; current = current.parentNode) {
    const key = current.$lrxKey;
    if (key !== undefined) return key;
    if (current.hasAttribute("data-lrx-key")) return current.getAttribute("data-lrx-key") ?? "";
    if (current === root) break;
  }
  return "";
}

export function listenDelegated(node, type, state, context, dispatch) {
  const handler = (event) => {
    const target = event.target;
    const actionNode = target && typeof target.closest === "function"
      ? target.closest("[data-lrx-action]")
      : null;
    if (!actionNode || !node.contains(actionNode)) return;
    dispatch(
      state,
      context,
      actionNode.getAttribute("data-lrx-action") ?? "",
      delegatedKey(actionNode, node),
      typeof target.value === "string" ? target.value : "",
      target.checked === true,
      typeof event.key === "string" ? event.key : "",
    );
  };
  node.addEventListener(type, handler);
  return () => node.removeEventListener(type, handler);
}

export function listen(node, type, state, refs, dispatch) {
  const handler = () => dispatch(state, refs);
  node.addEventListener(type, handler);
  return () => node.removeEventListener(type, handler);
}
