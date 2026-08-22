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

const templates = new WeakMap();

/** Deep-clones the static subtree that `build` produces. `build` runs once per
 * builder function; later calls clone the retained prototype. */
export function cloneTemplate(build) {
  let template = templates.get(build);
  if (template === undefined) {
    template = build();
    templates.set(build, template);
  }
  return template.cloneNode(true);
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

export function listenValue(node, type, state, context, dispatch) {
  const handler = (event) => dispatch(state, context, event.currentTarget.value);
  node.addEventListener(type, handler);
  return () => node.removeEventListener(type, handler);
}

export function listenChecked(node, type, state, context, dispatch) {
  const handler = (event) => dispatch(state, context, event.currentTarget.checked);
  node.addEventListener(type, handler);
  return () => node.removeEventListener(type, handler);
}

export function listenKey(node, type, state, context, dispatch) {
  const handler = (event) => dispatch(state, context, event.key);
  node.addEventListener(type, handler);
  return () => node.removeEventListener(type, handler);
}

export function listenFocus(node, type, state, context, dispatch) {
  const handler = () => dispatch(state, context);
  node.addEventListener(type, handler);
  return () => node.removeEventListener(type, handler);
}

export function listenSubmit(node, state, context, dispatch) {
  const handler = (event) => {
    event.preventDefault();
    dispatch(state, context);
  };
  node.addEventListener("submit", handler);
  return () => node.removeEventListener("submit", handler);
}

export function listenDelegated(node, type, state, context, dispatch) {
  const handler = (event) => {
    const target = event.target;
    const actionNode = target && typeof target.closest === "function"
      ? target.closest("[data-lrx-action]")
      : null;
    if (!actionNode || !node.contains(actionNode)) return;
    const keyNode = actionNode.closest("[data-lrx-key]");
    dispatch(
      state,
      context,
      actionNode.getAttribute("data-lrx-action") ?? "",
      keyNode && node.contains(keyNode) ? keyNode.getAttribute("data-lrx-key") ?? "" : "",
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
