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

// Deep-clones a static prototype subtree that generated code built once.
export function cloneTemplate(template) {
  return template.cloneNode(true);
}

let textWalker = null;

// The Text node that follows node in document order (descendants first), or
// null: TreeWalker(SHOW_TEXT).nextNode() from node. Reaches a cloned template's
// text slots without wrapping the elements between them; the shared walker
// keeps only the returned node current.
export function nextText(node) {
  textWalker ??= document.createTreeWalker(document, NodeFilter.SHOW_TEXT);
  textWalker.currentNode = node;
  return textWalker.nextNode();
}

// Marks node as a delegated-event key carrier for listenDelegated.
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

// Key of the nearest ancestor-or-self (up to root) carrying a setKey value or a
// data-lrx-key attribute; "" when none does.
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

export function makeDisposer(root, listenerDisposers, metrics, regions = [], gridWork = null) {
  let disposed = false;
  function dispose() {
    if (disposed) return;
    disposed = true;
    let firstError = null;
    for (const removeListener of listenerDisposers.splice(0)) {
      try {
        removeListener();
      } catch (error) {
        firstError ??= error;
      }
    }
    try {
      root.remove();
    } catch (error) {
      firstError ??= error;
    }
    if (firstError) throw firstError;
  }
  dispose.instrumentation = () => [
    metrics[0], metrics[1], metrics[2], metrics[3], metrics[4], metrics[5],
    metrics[6], metrics[7].slice(), metrics[8], metrics[9],
  ];
  dispose.regionInstrumentation = () => regions.map((region) => region.instrumentation());
  dispose.gridInstrumentation = () => gridWork?.slice() ?? [];
  return dispose;
}
