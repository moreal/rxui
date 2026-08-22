/** Typed control-event adapters (ADR-0013; a separate host since ABI 11):
 * each one extracts its fixed browser payload (value, checked flag, key,
 * focus change, or a prevented submit) and forwards it to a generated
 * dispatch function. Artifacts that only delegate events through
 * `listenDelegated` in leanrx_dom.mjs do not import this module. */
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
