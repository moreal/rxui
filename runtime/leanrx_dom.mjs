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

export function listen(node, type, state, refs, dispatch) {
  const handler = () => dispatch(state, refs);
  node.addEventListener(type, handler);
  return () => node.removeEventListener(type, handler);
}
