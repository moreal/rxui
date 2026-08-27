# ADR-0057: Trimmed attribute selection — the Add affordance

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0055 closed TodoMVC's component-scope add contract through the sealed
skip-if guard and recorded its third open question explicitly: "Other
component predicates stay raw. The ADR-0045 attribute selections still
compare raw fields; a trimmed `disabled` selection (graying the Add button
on a whitespace draft) is a separate decision." ADR-0056 restated the same
gap as its third open question after closing the Enter path.

TodoMVC grays its Add affordance while the new-todo draft is effectively
empty. The dispatch-layer contract already holds without it — both the Add
button's click and the Enter arm carry the ADR-0055 skip guard, so a
whitespace-only add is a whole-event no-op wherever it is triggered from —
but the affordance itself was inexpressible: the ADR-0045 `disabled`
selection compares a *raw* field against a literal, so `disabled={draft ==
""}` would keep the button live on a whitespace draft, disagreeing with the
guard the click would then hit. The vocabulary gap is exactly the subject
position: the selection needs to evaluate the same ASCII-trimmed equality
the guard evaluates.

## Decision

**Extend the ADR-0045 selection subject with the one sealed trim unary and
nothing else.** Each of the three sealed selection forms — the `class`
two-branch conditional, the `aria-pressed` reflection, and the `disabled`
property reflection — may now place its subject behind the ADR-0054/0055
`trim`:

```
disabled={trim draft == ""}
ariaPressed={trim field == "literal"}
class={if trim field == "literal" then "a" else "b"}
```

`AttrSelect` carries a `trimmed` flag; the subject stays one typed
`Field Γ String` (source or derived), the compared value stays one string
literal, and the `class` branches stay two static strings — the ADR-0045
rules are otherwise unchanged, including `LRX-VIEW-001` duplicate counting,
the `LRX-VIEW-032` native-button rule, and the `LRX-VIEW-026` bounds check.
The backend emits the subject as the ADR-0054 `asciiTrimPattern` replace —
`state[i].replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, "")` — inside the same
evaluate-compare-write sweep block behind the field's changed flag, riding
the shared `tx[8]`/`tx[9]` counters, the `attr:{index}:{name}` labels, and
the existing `setAttribute`/`setProperty` exports. A trimmed selection is
therefore *the guard's equality run by the sweep*: when the subject and
literal match a guard's (`trim draft` against `""`), the affordance and the
dispatch decision cannot disagree, by construction rather than by parallel
maintenance. The trimmed flag surfaces in the selection's planned-graph
debug marker (`select:disabled:trim:2`); dependencies are unchanged — trim
adds no reads.

The rejected alternatives:

1. **A general predicate vocabulary — rejected.** `disabled={expr}` over
   arbitrary boolean expressions would fork the selection language into the
   open frontier every ADR since 0043 has declined. The parity need is one
   normalization in subject position; the selection stays a table lookup,
   not an expression evaluator.
2. **Negation — rejected.** `disabled={!(trim draft == "")}` (enabling on
   emptiness) reads as an enabled-selection vocabulary; nothing in TodoMVC
   selects *enabled*, and admitting `!` invites the composed forms below.
   `LRX-VIEW-012` reports the sealed surface.
3. **Composed subjects and connectives — rejected.** `trim (a ++ b)`,
   conjunction, disjunction, or a second field would make the selection's
   dependency set and cache shape open-ended; the sealed subject keeps one
   field, one changed flag, one cache slot.
4. **Other applied heads — rejected.** The subject grammar admits exactly
   the `trim` identifier in head position (matched by name, ADR-0035 style,
   so `trim` stays an ordinary identifier); any other applied head is a
   general predicate in disguise and reports `LRX-VIEW-012`.
5. **An affordance-implies-contract reading — re-rejected.** ADR-0055
   rejection 2 stands: the disabled property is a UI reflection, not a
   dispatch-layer contract. The skip guard remains on both add paths, and
   the browser gate observes the guard directly — a synthetic click handed
   to the disabled button still returns before any transaction — so the
   no-op gate cannot go vacuous behind the grayed button.

**No host change and no runtime ABI bump**: the trimmed emission reuses the
`asciiTrimPattern` literal the scalar and row lowerings already print, and
selections without the flag emit byte-identical code — every other lab and
the js-framework-benchmark bundle are byte-identical under the performance
freeze. Components with any selection already stamp `attr-selections`;
Toggle Lab gains that feature (and the `attrRefs`/`attrCache` context
slots, its regions riding two slots later) by using its first selection,
which is the ADR-0045 layout rule, not a new one.

## Open questions

1. **Enabled-affordance selection stays out.** A selection that *enables*
   on emptiness (negation) is unrepresentable; TodoMVC has no such
   affordance, and admitting it is a separate vocabulary decision.
2. **Row-scope selections stay raw-or-trimmed asymmetric.** The ADR-0044
   row class selection and the ADR-0049 checked reflection still compare
   raw projected fields; no row affordance in TodoMVC needs a trimmed
   subject (the row editor's trim lives in the guard and the committed
   expression, ADR-0053/0054).
3. **The guard literal stays the empty string.** The selection compares
   against any literal, but the ADR-0055 guard it mirrors is sealed at
   `""`; a non-empty guard literal remains a separate decision nothing in
   TodoMVC needs.

## Consequences and limitations

- TodoMVC's Add affordance is now expressible and agrees with the dispatch
  guard: Toggle Lab's Add button carries `disabled={trim draft == ""}`,
  mounts disabled (the draft starts empty), stays disabled across
  whitespace-only typing, enables on the first non-whitespace character,
  and re-disables when the guarded add resets the draft — the commit sweep
  re-evaluating the trimmed subject behind the draft's changed flag and
  writing through `setProperty` only on a flip of the equality.
- A trimmed selection costs one `replace` per evaluation, only when its
  field changed in the transaction; the boolean/string cache keeps
  equal-value sweeps write-free (typing `"x"` → `"x "` evaluates once and
  writes nothing).
- The dispatch guard is untouched on both paths, and the ADR-0055
  whitespace-Add browser gate is reconstructed against the guard itself
  (synthetic click at the disabled button) plus the Enter path, so the
  contract stays pinned independently of the affordance.
- Row scope is untouched: no dispatcher, `reconcile6`, or row-vocabulary
  change; the key set stays sealed at Enter/Escape; the guard literal stays
  `""`; row guards stay single-field remove-or-commit; row scope still has
  no `s!`; branch cells stay single-level two-branch with exact
  click/dblclick agreement; and the parent-disposer gap of the region hosts
  is unchanged.

## Confirmation

Confirmed by the affordance round as drafted: the extension ships through
the generic backend with no host change and no runtime ABI bump — every
file of every other lab and of the js-framework-benchmark bundle
(`main.mjs` and manifest included) is byte-identical to the HEAD baseline
under the performance freeze; only Toggle Lab's module, manifest, and graph
change. Toggle Lab's browser gates pin the affordance (disabled on mount,
across whitespace-only typing, and after the guarded add's draft reset;
enabled on the first non-whitespace character, on a whitespace-padded valid
draft, and on an NBSP draft — the ASCII alignment), the guard-affordance
agreement (for every probed draft the disabled property equals the trimmed
emptiness the guard evaluates; where disabled, Enter is a whole-event
no-op; where enabled, the add appends), the equal-value sweep no-op (one
`attr:0:disabled:evaluated` and no write on a trailing space), and the
reconstructed ADR-0055 no-op (a synthetic click at the disabled button
returns before any transaction). The model gates pin the forged trimmed
selections (accepted with their trim flags, debug markers, and graph
sinks) beside the unchanged `LRX-VIEW-032` rejection on a trimmed subject;
the elaborator gate pins Toggle Lab's mounted selection (`disabled`, state
slot 2, empty literal, trimmed, on the Add button's path) and the guide's
`NewTodoMini` affordance; two compile-fail fixtures pin the sealed surface
(a non-`trim` applied head and a negated predicate, both `LRX-VIEW-012`);
and the artifact gate pins the mount-time property write, the sweep block's
trimmed equality with its labels and counters, the eleven-slot context, and
the `attr-selections` manifest feature beside the unchanged import shape.
