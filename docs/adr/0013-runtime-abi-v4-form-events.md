# ADR-0013: Bump the internal runtime ABI for form events

- Status: Accepted
- Date: 2026-08-19

## Context

M7 adds controlled DOM property writes and typed browser payload extraction for
text, checked, keyboard, focus, and submit events. ABI 3 hosts do not provide
these primitives, so accepting an M7 artifact under that version would fail at
module import or silently bypass the typed event contract.

## Decision

The internal JavaScript runtime ABI becomes version 4 for every artifact. The
DOM host adds `setProperty`, `listenValue`, `listenChecked`, `listenKey`,
`listenFocus`, and `listenSubmit`. Each adapter only extracts its fixed browser
payload and delegates to a generated function; parsing, validation, state
changes, scheduling, and effects remain compiler-generated responsibilities.
Compiler lowering consumes the closed `DomProperty`/`ControlEvent` constructors
through a shared typed helper rather than receiving property or event strings.
The additive `uniqueId` primitive allocates document-unique accessibility IDs;
it does not own component state or reactive work.

## Consequences

ABI-3 and ABI-4 artifacts/hosts must not be mixed. All existing scalar and
component manifest consumers move to version 4. The host surface grows, but it
does not discover dependencies or own form semantics. Later payload kinds
require another explicit ABI review.
ADR-0014 performs that later review and supersedes version 4 for current
artifacts while retaining this decision as the form-adapter history.

## Validation

Native tests lock the closed property/event GADTs. Generated form modules are
validated JavaScript ASTs, deterministic artifact checks require ABI 4, and
browser tests exercise payload extraction, controlled cursor behavior, submit
prevention, cross-instance isolation, post-disposal listeners, and hostile text.
Instrumentation retains the ABI-2 counter meanings; form-local validation is not
mislabelled as derived evaluation, and public traces redact raw key payloads.
Submit-authoritative text state uses `input`; a separate `change` listener is
observational. Temperature's active edited scale is an explicit Boolean state
slot so validation sinks remain functions of the checked store.
Existing Counter, Diamond, and Tabs
browser gates continue to run against the same additive host.
