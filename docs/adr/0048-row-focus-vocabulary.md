# ADR-0048: Focus transfer into freshly mounted row branch inputs

- Status: Accepted
- Date: 2026-08-25

## Context

The sealed row branch cell (ADR-0047) replaces a row cell's subtree when its
predicate changes branch, and the TodoMVC-shaped flow mounts a fresh edit
input at that moment. The bespoke `Backend.Todo` focuses that input on edit
entry; the generic backend had no focus vocabulary at all — no host export
touched `focus()`, and the sealed template surface had no way to request
it. The Branch Lab gate therefore clicked the input before typing, and a
keyboard-first user had to Tab into the fresh input by hand. Focus
*retention* was unaffected: a stable branch is updated in place and the
keyed region retains row nodes across reorder, so an already-focused input
keeps its focus and caret (pinned by the Branch Lab and NestLab gates).

## Decision

Adopt a sealed **`autoFocus` template marker on branch inputs** lowering to
one `focus(node)` host export, and reject the alternatives:

1. **The WHATWG `autofocus` attribute — rejected.** Its focusing steps run
   for documents and dialogs, not for elements inserted into a mounted
   page, so browsers do not reliably focus a dynamically appended
   `autofocus` input; shipping it would encode a behavior the platform does
   not promise.
2. **Focusing every fresh branch input implicitly — rejected.** Branch
   replacement also happens on commit (back to the label branch) and on
   field updates unrelated to editing; stealing focus on every replacement
   is a policy the compiler cannot know to be right, and implicit focus
   grabs are an accessibility hazard.
3. **Explicit opt-in marker — adopted.** A branch-subtree `input` may carry
   the bare `autoFocus` marker (`<input … autoFocus/>`), the first
   inhabitant of the surface grammar's bare-identifier attribute shape. It
   is validated like `value={…}` one rule further in: native inputs only,
   branch subtrees only, at most one marker per subtree — all
   `LRX-VIEW-036`, with the typed component view and the logical reference
   view rejecting the marker outright. The model carries it as one
   compiler-owned `autoFocus` flag on the sealed row element, so no
   attribute text ever reaches the emitter.

The update callback's replacement arm — and only that arm — calls the new
`focus(node)` DOM-host export on the incoming branch's marked input after
`append` (guarded by the same `want` flag that selected the builder), so
focus moves exactly when the user's action mounted an edit affordance. Row
mount (initial render, reconcile of appended rows) shares the branch
builders but never emits a focus call, and the stable-branch arm never
reaches one, so reorder and unrelated field updates cannot steal focus.

`focus(node)` is a new host export, so this ships as **runtime ABI 16**
with the mechanical manifest/test reference updates of the ABI bump
convention. The emitter imports `focus` — and stamps the `row-focus`
manifest feature — only when some region both declares update actions and
carries a marked branch input (an inert marker in an update-less region can
never fire), so components without a reachable marker emit byte-identical
modules, and the js-framework-benchmark module is byte-identical under the
performance freeze with only its manifest's ABI number changing.

## Confirmation

Confirmed by the focus round: Branch Lab's edit input carries `autoFocus`,
and the browser gates pin both directions — clicking Edit focuses the fresh
input with the reflected draft and typing proceeds keyboard-first, while
row mount keeps focus on the Add button, commit keeps it on the OK button,
and a structural reconcile of an editing row does not re-focus its editor.
The host export has a real-DOM unit gate beside the other DOM-host helpers,
three compile-fail fixtures pin `LRX-VIEW-036` (marker on a span, marker
outside a branch, marker in the typed component view), and the generated
module's single `focus` call site sits in the replacement arm — the
artifact gate counts it. The platform `autofocus` attribute was not needed,
confirming the draft's rejection.
