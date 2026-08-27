# ADR-0052: Sealed row key branching for keydown row events

- Status: Accepted
- Date: 2026-08-27

## Context

The TodoMVC editor commits on Enter and reverts on Escape, and the bespoke
`Backend.Todo` branches on `event.key` inside its keydown handler. The
generic backend's sealed rows cannot say this: a keydown row event
(ADR-0046) fires its one sealed update on *every* key — the delegated `key`
payload can be written into a field (`set lastKey pressed`) but never
compared — and ADR-0046 recorded the gap explicitly: "an Enter-only commit
needs a conditional vocabulary that does not exist in row scope". Toggle Lab
therefore commits through an OK button while its editor consumes keystrokes
only for the draft.

The host side already carries everything needed: `listenDelegatedCells` has
passed the event's `key` beside `value` and `checked` to every dispatch
since ABI 15, and the generated region dispatch function receives it as the
`eventKey` argument whether or not any action reads it.

## Decision

Adopt a **sealed key-branched row action** — key-literal equality branches
*inside* the generated region dispatch function, over the `eventKey`
argument the delegated dispatch already receives — and reject the
alternatives:

1. **New delegated kinds per key (`keydownEnter`, `keydownEscape`) —
   rejected.** The delegated kind vocabulary is compiler-owned and closed
   (ADR-0049 rejected the open kind table); minting one kind per key
   literal multiplies the listener registrations, the per-kind cell action
   arrays, and the ADR-0047 cross-branch agreement rules by the key set,
   and two sealed stages of one editor would dispatch through two
   listeners racing on the same element. Which keys select which stage is
   dispatch logic, not delegation structure.
2. **Key filtering in the host adapter — rejected.** Teaching
   `listenDelegatedCells` to filter by key (action arrays carrying key
   guards) is a host change and a runtime ABI bump for a comparison the
   generated dispatch function can perform on an argument it already
   holds — and the performance freeze wants the runtime byte-identical.
3. **A general payload-conditional vocabulary — rejected.** Arbitrary
   `if payload == "…"` conditionals in row right-hand sides would open the
   sealed `String` update language into an expression language with
   control flow (the fork ADR-0049 already declined for `Bool`). The
   branching ships as one closed action shape over a sealed key set
   instead.
4. **Key-branched action over the existing dispatch — adopted.** A typed
   `row` item may branch on its payload with the ADR-0051 table shape:

   ```
   row items keys (pressed : String) :=
     when "Enter" (set label draft, set mode "view")
     then when "Escape" (set draft label, set mode "view");
   ```

   lowering to `RowAction.keySelect` — a list of
   `(key literal, sealed simultaneous assignments)` arms. The declared
   parameter is the discriminant, named in the head and compared
   implicitly by each arm, exactly as a filter item's `by` field is
   (ADR-0051). A key outside the table is a **no-op**: no row scan, no
   field write, no `updateAt` queue entry, and no region trace — the
   dispatch runs its transaction shell (the delegated listener already
   fired) and commits nothing.

Sealing rules, checked by `ComponentSpec.check` (`LRX-VIEW-039`) with the
surface pinned by `LRX-ELAB-121`:

- key literals come from the sealed set `{"Enter", "Escape"}` — the two
  keys the TodoMVC contract branches on — and each appears at most once;
  the arm table is nonempty;
- each arm carries the ADR-0043 update obligations: nonempty simultaneous
  assignments over distinct in-bounds targets reading in-bounds row
  fields;
- arm right-hand sides are payload-free: the selection consumes the
  discriminant (open question 2);
- a key-branched event is payload-taking by construction and binds through
  `onKeyDown` exactly once on a native input (the ADR-0046 rules), and
  through no other kind — a key equality over a `value` or `checked`
  payload is meaningless;
- a `when` arm in a payload-less `row` item is rejected at elaboration
  (`LRX-ELAB-121`): the discriminant must be declared.

The dispatch function's `keySelect` branch emits, inside the existing
action match, one `eventKey === "literal"` conditional per arm wrapping the
ADR-0043 scan-evaluate-assign-queue sequence — so a matched key drains
exactly one retained-row `updateAt` through the commit sweep and a
non-matching key never reaches the row scan. **No host change and no
runtime ABI bump**: the emitted import line, `listenDelegatedCells`, and
the region record are untouched; the keydown listener registration and its
cell action array were already paid for by ADR-0046. Components without a
key-branched event emit byte-identical modules and manifests (the
js-framework-benchmark bundle is byte-identical under the performance
freeze); components with one stamp the `row-key-branches` manifest
feature.

## Open questions

Both resolved by the implementing round as drafted:

1. **No key-branched `remove` arm.** Emptiness of a field is not
   expressible in row scope (no guards), so an Enter-remove arm would fire
   on every Enter; TodoMVC's destroy-on-empty-commit stays a recorded gap
   for whatever ADR introduces row-field guards.
2. **The discriminant is not spellable as `payload` inside an arm.** The
   matched literal already fixes it, so admitting it would be a second
   spelling of a constant; `LRX-VIEW-039` rejects the reference.

## Consequences and limitations

- Enter-commit and Escape-revert compose with the ADR-0046/0047 editor
  loop: the per-keystroke `retype` keeps `draft` current, Enter's arm
  writes `label := draft` and leaves the edit branch, Escape's arm writes
  `draft := label` (the pre-edit value, since `label` changes only on
  commit) and leaves — so the next edit entry reflects the restored draft
  through the ADR-0047 value reflection. The branch replacement, focus
  transfer (ADR-0048), and dblclick agreement rules are unchanged.
- The key set is sealed at two literals; growing it (e.g. `Tab`,
  `ArrowUp`) is a deliberate vocabulary decision for a future ADR, not a
  template freedom. Arms select assignment stages only — a key-branched
  `remove` stays a recorded gap (open question 1), as do row-scope guards
  on field values.
- Every keydown on the bound input still dispatches: a non-matching key
  costs one empty transaction (begin/commit with zero writes and no
  queued positions), the price ADR-0046 already accepted for per-keystroke
  typed events.
- Row scope still cannot observe component state, `s!` interpolation, or
  non-`String` equality, and the parent-disposer gap of the region hosts
  is unchanged.

## Confirmation

Confirmed by the key-branch round as drafted: the extension ships through
the generic backend with no host change and no runtime ABI bump — Toggle
Lab's emitted import line is byte-identical to Branch Lab's, and every
file of the js-framework-benchmark bundle (`main.mjs` and manifest
included) is byte-identical to the HEAD baseline under the performance
freeze (only the `.leanrx-bundle-owner` marker differs, and it embeds the
output directory name). Toggle Lab's browser gates pin Enter committing
the draft as exactly one retained-row update with row identity preserved,
Escape restoring the pre-edit draft — the retype writes discarded, the
next edit entry pre-filled with the restored draft through the ADR-0047
reflection, and a commit-after-revert round-tripping it — and non-matching
keys (`ArrowLeft`, `Shift`) moving no region metrics while the editor
keeps its branch, value, and focus. `LRX-VIEW-039` is pinned by ten model
gates plus one compile-fail fixture and `LRX-ELAB-121` by two compile-fail
fixtures; the artifact gate pins the per-arm `eventKey` equalities inside
the dispatch function, the keydown listener registration, and the
unchanged import lines; and the emitter's scan-sequence extraction into
the shared helper is proven byte-identical by every other lab's unchanged
artifact gate. The rejected alternatives were not needed: no new delegated
kind, no host-side key filter, and no payload-conditional vocabulary.
