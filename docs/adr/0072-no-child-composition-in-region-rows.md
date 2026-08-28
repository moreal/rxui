# ADR-0072: Sealed row templates do not compose child components

- Status: Accepted
- Date: 2026-08-28

## Context

Static child composition (`<Chip tag="x"/>`) is sealed for component
views across depth (ADR-0069), width (ADR-0070), and multiplicity
(ADR-0071). The one place a capitalized head could still appear is a
sealed keyed-region row template (`region name (…) := jsx% …`,
ADR-0041). This round surveyed what actually happens there.

The survey found the boundary already closed, but by accident of the
tag whitelist rather than by contract. `collectComponentHeads` walks
only view items (`leanrxItemView`), so a capitalized head in a region
item never joins the child table; but it also never lowers to
`View.child`, because `lowerRowElement` treats every head as a plain
tag and hands it to `leanrx_jsx_tag%`, which rejects any
non-whitelisted identifier with the generic
`LRX-VIEW-007: unsupported element <Chip>`. The backend
`childMounts.find?` miss (`LRX-BE-029`) is unreachable from this
path. So the failure is early — elaboration-time — but the
diagnostic is misleading: "unsupported element" reads as a tag
whitelist gap (the `<h4>` message), inviting the user to ask for the
tag, when what they attempted is composition in a place whose
contract excludes it.

The contract conflict is structural. A sealed row template is a
static tree with field text, class/attr selections, and delegated
row events; its lifecycle is per-row `updateAt` and dispose driven by
the region backend. A child component mount has its own lifecycle: a
disposer that must be composed into its parent's disposal and
republished on `children` (ADR-0066). Rows are created and destroyed
per `append`/`remove` at runtime, so composing a child per row would
require a per-row child disposer republication contract — mounting on
row create, disposing on row remove, and re-publishing a dynamic
`children` inventory per row. That is a new lifecycle contract, not
an extension of the static child table.

## Decision

**Reject with a dedicated elaboration diagnostic; change nothing
else.** `lowerRowElement` now checks `componentHead?` on every
element head before lowering attrs, and throws

```
error[LRX-ELAB-131]: a sealed row template does not compose child
components; mount <Chip/> from the component view instead (ADR-0072)
```

at the head's own span. The check runs before attr lowering so a
component head always gets the composition diagnostic, never a
stray unknown-attribute error from its prop-shaped attrs. Nested
heads are covered by the same check because `lowerRowChild`
delegates every element child back to `lowerRowElement`.

The witness is `Test/fixtures/compile-fail/ChildInRegionRow.lean`
(registered in `scripts/check_compile_fail.sh`): a checked `Chip`
spec is in scope — pinning that the rejection is about the row
contract, not about a missing `_spec` (`LRX-ELAB-130`'s concern).

## Consequences

- The diagnostic is elaborator-only: no generated module, manifest,
  or host change; byte identity and the benchmark size gate stand
  trivially.
- `LRX-VIEW-007` remains the tag-whitelist diagnostic for genuinely
  unknown lowercase tags in row templates; capitalized heads are
  carved out to `LRX-ELAB-131` before reaching it.
- The static-composition story now has an explicit outer edge: child
  components mount from component views only. Together with
  ADR-0069/0070/0071 this closes the composition surface — every
  place a `<Child/>` head can appear is either supported and
  witnessed, or rejected with a dedicated diagnostic.

## Open questions

1. **Per-row child composition stays unsupported, not unsupportable.**
   Supporting it needs a per-row lifecycle contract: mount on row
   create, dispose on row remove, and a dynamic per-row `children`
   republication replacing the static ADR-0066 inventory. That is a
   full round (or more) of its own, and no lab currently needs it;
   revisit only with a concrete consumer.
