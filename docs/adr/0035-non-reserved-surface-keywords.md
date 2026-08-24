# ADR-0035: Parse surface keywords as plain identifiers

- Status: Accepted
- Date: 2026-08-24

## Context

The `component` command and the `jsx%` attribute grammar declared their
keywords as syntax atoms (`state`, `derived`, `event`, `view`, `onClick`,
`id`, `ariaLabel`), so any scope opening `LeanRxDsl` lost those words as
identifiers — ADR-0034 recorded renamed parameters (`model`), escaped fields
(`«view»`), and late scope opening as accepted friction. An experiment with
Lean's non-reserved keyword parser (`&"state"`) showed it cannot lead a
syntax-category alternative: category dispatch indexes rules by their leading
token, and an identifier token never reaches a rule indexed under a
non-reserved atom, so `&"…"`-led item rules simply never fire.

## Decision

Remove the reserved atoms instead of trying to soften them:

- `component` items parse as identifier-led rules
  (`ident ident ":=" …`, `ident ":=" …`, plus the typed forms of ADR-0036),
  and the elaborator dispatches on the leading identifier's name with the
  stable diagnostic `LRX-ELAB-003` for unknown roles. `state`, `derived`,
  `event`, and `view` are ordinary identifiers everywhere, including scopes
  that open `LeanRxDsl`.
- `jsx%` attributes keep only `class` and `type` as atoms — both are Lean
  keywords and cannot parse as identifiers — and route every other attribute
  through the generic `ident = …` rules. Name dispatch during lowering keeps
  the closed whitelist and the `LRX-VIEW-008`/`-010`/`-012`/`-013`
  diagnostics; `onClick`, `id`, `ariaLabel`, and the new payload attributes
  are ordinary identifiers.
- The event-step words `set` and `dispatch` (ADR-0036) are recognized as
  application heads of parsed terms, not tokens; the sequence separator
  `then` and the command head `component` reuse existing Lean tokens.
- `key` in the keyed-list surface stays a reserved token: it follows a term
  position (`for x in items key k => …`), where a non-reserved word would be
  swallowed as an ordinary application argument of `items`. The escape hatch
  remains `«key»`, and the scope cost is limited to scopes opening
  `LeanRxDsl`.

## Consequences

- Existing sources parse unchanged: the old spellings (`state count := …`)
  are the same character sequences, now parsed as identifier-led items, and
  the generated `Counter.mjs`/`DiamondLab.mjs` modules stay byte-identical.
- Role typos surface at elaboration (`LRX-ELAB-003` with the role name)
  instead of at parse time; attribute typos keep `LRX-VIEW-008`.
- The recorded ADR-0006/ADR-0034 identifier trade-off shrinks to `key` and
  `section` (a Lean command keyword excluded from the tag surface).
