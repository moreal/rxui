# ADR-0042: Immutable props cross the mount ABI as a positional array

- Status: Accepted
- Date: 2026-08-25

## Context

ADR-0039 composes stateful children by static module import, but a parent had
no way to configure a child: `ImmutableProp` (M6) existed only for term-level
component calls in the logical view. The candidate designs for the checked
path were (a) baking prop values into the child's module bytes — which forks
one module per instantiation and breaks module-level sharing — and (b)
passing values at mount time through the existing `mount` export.

## Decision

Immutable props travel **through the mount ABI as one positional array**:

1. **Child declaration.** A `prop name : String;` item adds a `PropSpec` to
   `ComponentSpec.props` (stage 1 fixes the payload type to `String`,
   `LRX-ELAB-113` otherwise). A `{name}` text child in the child's own view
   lowers to the sealed `View.propText index` position — a mount-time
   constant, not a sink: the generated module reads `props[index]` once into a
   text node and never revisits it. Updates cannot target props (they are not
   schema fields), so immutability is structural.
2. **Mount signature.** A child with props exports
   `mount(target, props)`; a component without props keeps `mount(target)`
   byte-identically. `exports` stays `["mount"]`, the runtime ABI stays 15,
   and the manifest discloses the `immutable-props` feature.
3. **Parent binding.** `<Child name="text"/>` with all-literal attributes
   lowers to `View.child` carrying ordered name/value pairs, and the parent's
   module calls `$lrx_child_i(parent, ["text", …])` mid-mount. The values are
   compile-time literals in the parent module — no runtime marshalling, no
   object allocation shape to keep stable.
4. **Cross-module checking at elaboration.** The parent's jsx elaborator
   evaluates the child's `ComponentSpec.propNames` (the same isolated
   compile-time evaluation the component command uses for validation
   messages) and requires the attribute names to match the child's declared
   names *and order* exactly — including the empty case: an attr-less
   `<Child/>` whose spec declares props is rejected. Both directions are
   `LRX-ELAB-112`. This keeps the emitted positional array aligned with the
   child's `props[index]` reads without any runtime name lookup.

Nest Lab dogfoods one static prop (`<Pulse title="Pulse child"/>` rendering
through `#pulse-title`) under the Chromium gates.

## Consequences and limitations

- Parent→child configuration exists with zero runtime cost beyond one array
  literal per child instance, and one child module serves every
  instantiation.
- Stage 1 limits: `String` payloads only; props render only as static text
  positions (not attributes, not expressions); no defaults — parents must
  bind every declared prop; a hand-written `mount` call must pass a matching
  array (the manifest's `immutable-props` feature is the signal). Reactive
  parent→child data flow remains future work and is orthogonal: it would ride
  events, not this array.
- Child instrumentation is still unreachable through the parent disposer
  (ADR-0039 limitation, unchanged).
