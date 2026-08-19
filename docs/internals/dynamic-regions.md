# Dynamic region contract

M8 adds local dynamic regions after the static scalar path is already stable.
Static scalar sinks remain direct node/property writes. Only a declared region
may reconcile shape; LeanRx does not introduce a root-wide or general Virtual DOM.

`Region.LogicalNode` is a pure reference value for native/differential tests. It
is not a browser representation and is never serialized into generated runtime
state. Optimized region models retain opaque mount tokens so tests can distinguish
logical equality from DOM identity.

The first conditional model has two operations:

- a same-branch update retains its token and records at most one direct scalar
  update;
- a branch transition disposes the old token exactly once and mounts one new
  token.

Lean proves that the optimized conditional result has exactly the reference
logical node. Browser lowering and DOM identity/disposal remain in the TCB and
will be covered when the local region host lands.

The positional model retains mount tokens for the common prefix, performs direct
logical-node updates at those positions, creates only an appended suffix, and
disposes only a removed suffix. Lean proves that its optimized mounted projection
equals full target-list recomputation. Positional identity deliberately follows
index, not application keys; reorder-sensitive collections must use the later
keyed region.
