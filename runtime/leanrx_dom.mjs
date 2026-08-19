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

export function listen(node, type, state, refs, dispatch) {
  const handler = () => dispatch(state, refs);
  node.addEventListener(type, handler);
  return () => node.removeEventListener(type, handler);
}
