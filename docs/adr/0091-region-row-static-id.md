# ADR-0091: The static-id rule follows the multiplication, not the module boundary

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0090 closed the transitive half of the static-id rule and stated the
half it left open. `LRX-ELAB-135` rejects composing a child whose mounted
tree carries a static `id` into a sealed row template, and the trail it
reads folds the child's own view, *the row templates of every region that
child declares*, and every component it composes. So this is rejected:

```lean
component Cuff … where {
  region marks (tag) := jsx% <li id="mark"> [{tag}];   -- as a row child: rejected
}
```

and this, the same three lines in the component doing the composing, is
not:

```lean
component Roster … where {
  region roster (label) := jsx% <li id="row"> [{label}];   -- accepted today
}
```

One `id`, one region, one instance per row, one document with N copies of
`row` in it — and the compiler's answer depends on which file the region
was declared in. It is the only place left where the same failure is
rejected on one side of a module boundary and admitted on the other, and
the asymmetry is visible in the fold itself: `staticIdTrail` consults a
component's own region templates when answering *for a composer* and is
never consulted about the component under the cursor.

## Decision

**The line moves: the rule follows the multiplication.** A static `id`
is rejected wherever the *compiler* instantiates the template that
carries it more than once, and left to the author wherever the compiler
mounts it once. A component's own region row template is rejected at the
model layer under the new `LRX-VIEW-046`.

This replaces two sentences.

- **ADR-0071's** was "the pipeline does not scout for duplicate ids;
  the axe `duplicate-id` gate catches them." It stands for everything the
  author mounts once — `<ul id="roster">` in a view, `id="pulse-title"`
  in a component composed in a view — and those remain accepted with no
  diagnostic. What it no longer covers is a template the compiler itself
  repeats.
- **ADR-0090's** was "the compiler polices templates the author is *not
  looking at* — a child module's tree, reached by name — and leaves ids
  in the template under the cursor to the author." That drew the line at
  *authorship*, which explained the child rule but could not explain why
  a child's region templates were folded in, and had to leave a hole to
  keep the story straight. Authorship is the wrong invariant: the author
  of `<li id="row">` wrote one id and did nothing wrong at all until the
  region machinery turned one into N. **The duplication is created by the
  compiler's emission, so the compiler owns it** — in the author's own
  file or three modules away. The one-instance case is unchanged
  precisely because there the compiler adds nothing to what was written.

Both existing rejections re-derive from the new line: a row-composed
child's tree mounts once per row (`LRX-ELAB-135`), and a region's row
template mounts once per row (`LRX-VIEW-046`). Nothing else in the
language multiplies a template, so the rule is closed.

**Where the rejection lives: the model layer, on the existing
predicate.** `validateRegions` already walks the region table with each
region's declaration span in hand; the new check is one `if` in that loop
whose decision is `RowNode.hasStaticId` — the very function
`ComponentSpec.staticIdTrail` folds. The alternative was the elaborator,
in `lowerRowAttrs`, where the offending `id=` token's span is exact.
Rejected for two reasons:

- **One predicate, two readers, no drift.** With the check reading
  `hasStaticId`, the statement "this component mints ids per row" and the
  statement "this component is rejected" are the *same walk*. A separate
  attribute test in `lowerRowAttrs` would be a second encoding of the
  rule, and a future `RowNode` constructor carrying attributes would have
  to be remembered in both places or the two would silently disagree.
- **It is a fact about specs, not about syntax.** `ComponentSpec.check`
  is the contract every consumer reads — the backend, the CLI, a
  hand-written spec that never passes through `component` at all. An
  elaborator-only rejection would leave `check` accepting a spec whose
  regions the trail simultaneously reports as id-minting.

The cost is span granularity: the diagnostic names the region
declaration rather than the `id=` token. That is the right granularity
anyway — the region is the thing that multiplies, so the region is what
the message is about — and the compile-fail gate pins the location
(`RegionRowStaticId.lean:21:3`) so it cannot decay to `<generated>`.

**A new number, not another extension of `LRX-ELAB-135`.** ADR-0090
already wrote the reason down: extending 135 was justified there because
the rule *and the repair* were unchanged and only the offending
attribute's location differed. Here the rejected construct is different
(a region declaration, not a child reference), the layer is different
(the model validator, not the row lowering), and 135's message — "child
component X carries a static id" — has no child to name. The spec'd-head
misuse map stays 112 / 130 / 131 / 132 / 133 / 135; `LRX-VIEW-046` joins
the region validations beside `LRX-VIEW-045`.

**ADR-0090's option (c), lifting the whole id rule to the model layer:
declined, not deferred.** It is now *possible* — `spec.children` carries
trails, so `validateRegions` could match each `RowNode.child` name
against the child table and read the trail there. It is still not worth
doing. The row-child arm would trade an exact reference-site span for a
name-to-table lookup that can miss (a `RowNode.child` holds a short name;
the table is keyed by the same string, so the coherence of the two is an
extra obligation nothing currently owes), and it would buy no rejection
that does not already happen. The rule is stated once — here — and
enforced at the layer where its datum lives: an attribute is in the
model, a resolved child name is in the elaborator's scope. ADR-0090's OQ1
is closed by rejection, and (c) is closed by this paragraph.

## Consequences

- No codegen change of any kind. No example carries an `id` in a row
  template, so nothing in any bundle moves: all 155 generated files
  across the nineteen generators — 66 `.mjs`, 20 `.graph.json`, every
  `.manifest.json` — are byte-identical under the stash/rebuild protocol,
  `graphHash` included, because no example source line moved either. The
  size gate, the manifests and BENCHMARK.md stand unre-measured. No host
  change; runtime ABI stays 17.
- The compile-fail set gains `RegionRowStaticId`, whose region template
  carries `id="roster-row"` while its view keeps `<ul id="roster">` — the
  two sides of the line in one fixture. `RowChildStaticId` and
  `RowChildNestedStaticId` are untouched and still report ADR-0075's and
  ADR-0090's wordings.
- `Test/Component/Model.lean` pins the rejection on forged specs at the
  row root, one cell down, and inside one subtree of a two-branch cell —
  the whole domain of `hasStaticId` — plus the accepting cases: an
  id-free region passes, and a component whose *view* carries an id
  passes `check` while still answering `["Roster"]` for a composer. That
  last pair is the new line in one assertion: one question, two scopes.
- The trail's region arm stays and stays total. It now speaks only for
  specs the validator has not seen, since every checked component's
  regions answer `false`; keeping it is what makes the two readers agree
  by construction rather than by review.
- The forged `trailSpec` helper gained one declared state value so the
  same specs can be run through `check`, not only through the trail.

## Open questions

None. Every template the compiler instantiates more than once is now
policed, at the layer where its attribute lives, and single-mount ids
remain the author's and the axe gate's.
