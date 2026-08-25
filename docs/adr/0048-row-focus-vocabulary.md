# ADR-0048: Focus transfer into freshly mounted row branch inputs

- Status: Proposed (decision draft)
- Date: 2026-08-25

## Context

The sealed row branch cell (ADR-0047) replaces a row cell's subtree when its
predicate changes branch, and the TodoMVC-shaped flow mounts a fresh edit
input at that moment. The bespoke `Backend.Todo` focuses that input on edit
entry; the generic backend has no focus vocabulary at all — no host export
touches `focus()`, and the sealed template surface has no way to request
it. The Branch Lab gate therefore clicks the input before typing, and a
keyboard-first user must Tab into the fresh input by hand. Focus *retention*
is unaffected: a stable branch is updated in place and the keyed region
retains row nodes across reorder, so an already-focused input keeps its
focus and caret (pinned by the Branch Lab and NestLab gates).

## Decision (draft)

Adopt, in a future round, a sealed **`autoFocus` template marker on branch
inputs** lowering to one `focus(node)` host export, and reject the
alternatives:

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
3. **Explicit opt-in marker — adopted direction.** A branch-subtree `input`
   may carry one compiler-owned `autoFocus` marker (surface sugar on the
   sealed template, validated like `value={…}`: inputs only, branch
   subtrees only). The update callback's replacement arm — and only that
   arm — calls a new `focus(node)` DOM-host export on the marked input
   after `append`, so focus moves exactly when the user's action mounted an
   edit affordance. Row mount (initial render, reconcile of appended rows)
   never focuses.

`focus(node)` is a new host export, so shipping this takes runtime ABI 16
plus the mechanical manifest/test reference updates (the ABI bump
convention); that cost is why this round records the draft instead of
implementing it — ADR-0047 held its ABI-freeze bar and no sibling change
needed the bump.

## Confirmation bar

This draft is confirmed (Status → Accepted) when a follow-up round ships
the marker and `focus(node)` under ABI 16 with a browser gate showing edit
entry focusing the fresh input (and reorder/commit not stealing focus); it
is revised instead if the implementation shows the platform `autofocus`
attribute suffices or a different opt-in surface is needed.
