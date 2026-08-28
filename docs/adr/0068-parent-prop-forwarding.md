# ADR-0068: Forward a parent's immutable prop into a child prop

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0042 sealed child props to `name="text"` literals, and ADR-0067
carried the boundary forward as its OQ1: a parent could not thread its
own mount-time constant into a child's prop, so `Pulse` had to pass
`Tick` a fresh literal instead of the `title` it received from
`NestLab`. This round surveyed whether the minimal static form —
`<Tick label={title}/>` where `title` is one of the parent's own
declared immutable props — is expressible in the existing pipeline.

**The survey found every stage one small extension away.** The
elaborator already resolves declared prop identifiers positionally
(`rewritePropRefs` turns `{title}` text children into `propText%
index` where the inventory exists), the backend already reads the
parent's positional mount argument (`createText(props[0])` for prop
texts) and already threads `propsName` through `mountChildren`, and
`JsAst` already has `Expr.index`. What was missing: the child-element
attr shape admitted only `name="text"` (`childElementHead?` /
`literalPropPairs`), `View.child` carried `List (String × String)`
(literals only — identifier references need a sum), and
`leanrx_jsx_component_props%` took `str*` pairs.

Reactivity is explicitly out of scope: a state or derived value in a
child prop position would contradict the immutable-prop contract
(child props are read once at mount and never revisited), so
forwarding admits mount-time constants only.

## Decision

**Adopt exactly one forwarding convention: a child prop value may be
one declared immutable prop identifier of the parent, and nothing
else.** `<Tick label={title}/>` lowers through a new `ChildProp` sum —
`View.child` props become `List (String × ChildProp)` with `.lit
value` (ADR-0042 literals) and `.forward field` (the parent's prop
declaration index) — and the backend emits the nested mount argument
as `props[field]`, the parent's own positional mount argument.
Concatenation, interpolation, `rx%` staging, state, and derived
references are not forwardable; a parent without props has nothing to
forward.

The pipeline extensions, each at the surveyed seam:

- `rewritePropRefs` additionally rewrites `name={parentProp}` attrs to
  the internal `name = propRef% index` shape — scoped to capitalized
  child-shaped heads so a controlled input's `value={field}` binding
  can never be claimed by a prop of the same name, and resolved where
  the declared inventory exists.
- `childElementHead?` accepts the forwarding attr (pre-rewrite ident
  form and post-rewrite `propRef%` form), so `collectComponentHeads`
  still registers the child exactly when the lowering will reference
  it.
- `leanrx_jsx_component_props%` takes `(str <|> num)*` pairs — a num
  value is a forward — and keeps the ADR-0042 LRX-ELAB-112 name/order
  check unchanged. A forward has no typed-application meaning, so a
  head without a checked spec reports the new `LRX-ELAB-130`.
- `ComponentSpec.check` gains `LRX-VIEW-044`: a `.forward` index must
  be within the parent's declared prop count.

## Consequences

- NestLab is the pinned witness: `Pulse` now forwards `label={title}`
  into `Tick`, so the generated `Pulse.mjs` mounts the grandchild with
  `$lrx_child_0(node_0, [props[0]])` (pinned in
  `Test/js/nest_artifacts.mjs`) and the browser gate shows the
  root-supplied literal two levels down — `#tick-label` reads
  `"Pulse child"`, the value `NestLab` passed to `Pulse`.
- No host or ABI change: the mount signature `mount(target, props)`
  and the positional prop array are exactly ADR-0042's; only the call
  site of the nested mount changed shape, and only in modules that
  forward. Every module outside the nest bundle is byte-identical; the
  benchmark bundle and its size gate stand.
- `MountedChild.props` and `MountNode.child` carry `ChildProp`; the
  elab pins (`Test/Elab/Component.lean`, `Test/Docs/LanguageGuide.lean`)
  spell `.lit`/`.forward`, and the audit manifest registers the two
  generated `injEq` lemmas.
- The guide teaches the sealed surface beside the ADR-0042 section
  with the compiled `PropForwardMini` snippet;
  `Test/fixtures/compile-fail/ForwardWithoutSpec.lean` pins
  `LRX-ELAB-130`.
- ADR-0067 OQ1 is discharged: the prop boundary is now the reactive
  one — constants flow any depth, signals do not cross mounts.

## Open questions

1. **Reactive child props stay rejected by construction.** If a later
   round wants live parent→child data flow, it needs a different
   contract than immutable props (a subscription surface across the
   mount ABI), not a relaxation of `ChildProp`.
2. **Transitive re-forwarding is untested.** A three-level chain
   (`label={title}` where `title` is itself received, i.e. grandparent
   → parent → child of one constant) should work — each level reads
   its own `props[i]` — but no lab pins it; the two-level NestLab
   forwards the root's literal exactly once.
