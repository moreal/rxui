# ADR-0054: Sealed row expression trim for the TodoMVC commit contract

- Status: Accepted
- Date: 2026-08-28

## Context

TodoMVC trims an edit before committing it: a draft of spaces is an empty
commit (the todo is destroyed), and a committed title is stored without its
surrounding whitespace. ADR-0053 shipped the remove-if guard but compared
the raw field, and its first open question recorded the gap explicitly:
"TodoMVC trims the draft before the emptiness test; the sealed guard
compares the raw field, so a whitespace-only draft commits as a whitespace
label. Trimming is a row-expression vocabulary decision (a `trim` unary
beside `append`), not a guard shape, and stays a recorded gap." Toggle Lab
therefore removed rows only on the exactly-empty draft and stored labels
with their whitespace.

The hand-written Todo backend has always trimmed its add path — emitting
`value.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, "")`, the ASCII strip aligned
with Lean's `String.trim` — so the normalization itself is neither new to
the emitted code shape nor to the runtime: it is a pure expression over a
string the dispatch function already holds.

## Decision

Adopt a **sealed `trim` unary in the row expression language** — ASCII
whitespace stripped from both ends, usable wherever sealed row expressions
already appear — and let the ADR-0053 guard compare it by generalizing the
guard's subject to a sealed row expression restricted to one (optionally
trimmed) field projection. The rejected alternatives:

1. **A general string-function vocabulary — rejected.** `toLowerCase`,
   `replace`, `slice`, and friends would turn the sealed `String` update
   language into a library surface with an open growth frontier — the same
   fork every row-scope ADR since 0043 has declined for control flow,
   declined here for combinators. TodoMVC parity needs exactly one
   normalization; `trim` ships as one closed unary and nothing else.
2. **A trim flag on the guard record — rejected.** ADR-0053 resolved that
   trimming is an expression decision, not a guard shape: a `trimmed :
   Bool` beside the guard field would grow the predicate language and
   leave the commit path — `set label (trim draft)` — inexpressible. This
   ADR is a row-expression vocabulary extension, **not** a guard
   vocabulary extension: the guard stays one single-field `String`
   equality against one literal; what generalizes is only that its subject
   is now a sealed row expression, pinned by `ComponentSpec.check`
   (`LRX-VIEW-040`) to `field` or `trim field` — never a literal, payload,
   concatenation, or nested composition.
3. **Trim in the host adapter or runtime — rejected.** Normalizing inside
   `listenDelegatedCells` or a host export would be a runtime ABI bump for
   a pure expression the dispatch function can evaluate on data it already
   resolved — and the performance freeze wants the runtime byte-identical.
4. **A sealed `trim` unary in `RowExpr` — adopted.** The surface is
   `trim field` or `trim (expr)` at any row-expression position
   (`LRX-ELAB-115` names the vocabulary otherwise), lowering to
   `RowExpr.trim`. The guard surface admits the trimmed subject —
   `if trim draft == "" then remove else (set label (trim draft), …)` —
   with any other subject expression rejected at the surface
   (`LRX-ELAB-122`) and at the model (`LRX-VIEW-040`).

The backend lowers `RowExpr.trim` to the ASCII-whitespace `replace` the
hand-written Todo backend has always emitted (`asciiTrimPattern`, aligned
with Lean's `String.trim` — deliberately not the Unicode-aware
`String.prototype.trim`), and the guard subject rides the same `rowExprJs`
lowering the commit assignments use: a raw-field guard emits the identical
`row_item[i] === "literal"` comparison as before. **No host change and no
runtime ABI bump**: the emitted import line, `listenDelegatedCells`, the
region record, and every listener registration are untouched. Components
without a trim emit byte-identical modules and manifests (the
js-framework-benchmark bundle is byte-identical under the performance
freeze); components with one stamp the `row-trim` manifest feature.

## Open questions

1. **Component scope stays untrimmed.** `trim` lives in `RowExpr` only;
   the component-state expression language (`RxExpr`) has no trim, so a
   component-scope add path cannot normalize its draft. Whether TodoMVC's
   top-level new-todo input needs an `RxExpr` trim (or arrives as a keyed
   region append through row vocabulary) is the next parity decision.
2. **Other sealed predicates stay raw.** The ADR-0050 predicate removal
   (`remove region (field == "literal")`), the ADR-0051 filter arms, the
   ADR-0044 class selection, and the ADR-0049 checked reflection still
   compare raw fields. Nothing in TodoMVC needs them trimmed; growing any
   of them is a separate vocabulary decision.

## Consequences and limitations

- The full TodoMVC editor commit contract is now expressible: per-keystroke
  `retype` keeps `draft` raw and current, Enter and OK guard on
  `trim draft == ""` (whitespace-only drafts destroy the row), and a miss
  stores the trimmed label. Toggle Lab additionally re-mirrors the draft to
  the trimmed value in the same simultaneous stage — `set draft (trim
  draft)` — keeping its draft-mirrors-label invariant, so the next edit
  entry starts from the stored label exactly as TodoMVC's editor does.
- `trim` composes with the existing vocabulary anywhere a row expression
  sits — assignments, `exprText` row text, `value` reflections, region
  broadcasts — and `trim (expr)` may wrap any sealed expression. Only the
  guard subject is pinned to the single (optionally trimmed) field
  projection: the single-field equality invariant of ADR-0053 is
  unchanged.
- A trimmed guard costs one `replace` call on the dispatching row's field
  at dispatch time — no new sweep, no new transaction shape, and the
  guard-hit removal path is byte-for-byte the sealed `remove` sequence.
- Row scope still cannot observe component state or `s!` interpolation;
  the key set stays sealed at Enter/Escape; and the parent-disposer gap of
  the region hosts is unchanged.

## Confirmation

Confirmed by the trim round as drafted: the unary ships through the
generic backend with no host change and no runtime ABI bump — Toggle Lab's
emitted import line is unchanged, and every file of every other lab and of
the js-framework-benchmark bundle (`main.mjs` and manifest included) is
byte-identical to the HEAD baseline under the performance freeze, which
also pins that a raw-field guard's emission is untouched by the subject
generalization. Toggle Lab's browser gates pin Enter on a whitespace-only
draft removing exactly the dispatching row (one disposal, one survivor
update from the dirty reconcile, no mount, no move, survivor DOM identity
preserved, counts following) and the trimmed store — `"  x  "` commits as
`"x"`, the re-entered editor reflects the trimmed draft, and the OK button
agrees through the guarded commit. `LRX-VIEW-040` is pinned by model gates
(the good trimmed guard and trimmed key arm plus the non-subject
rejections: a literal, a trimmed literal, a payload, a concatenation, an
out-of-bounds trimmed field) and the surface by two compile-fail fixtures
(a non-subject guard expression under `LRX-ELAB-122`, a trim over an
unknown field under `LRX-ELAB-115`); the artifact gate pins the trimmed
guard and commit sequences inside the dispatch function beside the
unchanged import lines and the `row-trim` manifest feature. The rejected
alternatives were not needed: no string-function library, no guard-shape
flag, and no host-side normalization.
