# Commands, resources, and foreign-port contract

M9 keeps every application update pure. `Cmd Msg` is data returned by an update,
with closed constructors for no work, ordered batches, timeouts, storage reads
and writes, HTTP, typed foreign ports, and cancellation. Derived expressions and
view rendering cannot execute commands. Generated event/result handlers invoke
the effect host only after their pure state update/render phase.

## Ownership and cancellation

`Effect.Handle` has a private constructor and advances only through `first` and
`next`. Each mounted effect host owns a handle map. Starting work removes any
older operation with the same handle; replacement, explicit cancellation, and
component disposal remove ownership before invoking the platform cancel action.
Any promise that resolves afterward finds no owned entry and cannot deliver.
Every rejection becomes an `Effect.Error`; no promise rejection is intentionally
left unobserved. Completion is bound to the exact owned entry, not only its
numeric handle, so a non-cooperative replaced operation cannot delete or deliver
through a newer operation that reused the handle. Cancel callbacks run only
after ownership removal. Throws and rejected cancel promises are normalized into
the effect host's copied `errors()` observation rather than interrupting cleanup;
the ordinary DOM/region disposer still runs.

`Resource α` explicitly represents idle, loading, success, failure, and
cancelled states. `settle` and `cancel` change a loading resource only for the
matching handle. Lean proves `settle_stale` and `cancel_stale` for mismatched
handles, both with the exact reviewed `[propext]` footprint recorded in
ADR-0005. Reducers also retain the active request key and reject stale result
messages, providing a second pure guard at the application boundary.

## Host adapters

`runtime/leanrx_effects.mjs` is an injected, mount-local interpreter surface:

- timeouts receive configurable set/clear functions;
- storage receives a configurable Storage-like object;
- HTTP receives configurable `fetch`, applies query pairs with
  `URLSearchParams`, and owns an `AbortController`;
- foreign commands resolve a named adapter with an optional cancel callback.

The DOM host still performs no scheduling or dependency discovery. The effect
host receives explicit state, context, handle, result decoder, and delivery
function. `makeEffectDisposer` cancels all owned operations before delegating to
the ordinary DOM/region disposer. ABI 6 exposes command starts/cancellations at
standard instrumentation indices 8/9 and through a focused defensive snapshot.

## Foreign ports

Applications cannot embed JavaScript. A `ForeignPort ι ο` has a private
constructor and declares:

- stable name;
- input/output `PortTypeId` wire descriptions;
- synchronous or asynchronous mode;
- cancellation behavior;
- possible error codes;
- trust and security notes;
- deterministic native mock.

`PortTypeId` is deliberately separate from sealed reactive `RuntimeTypeId`.
Callers supply a type-indexed `PortRep α`; nominal `PortRecord name α` wrappers
tie record metadata to the corresponding Lean payload, and a compile-fail gate
rejects mismatched descriptions. Structured array/record wire descriptions
therefore cannot create new reactive equality plans, lie about the declared Lean
signature, or make arbitrary Lean structures browser-lowerable. Component
manifests serialize the complete consumed-port declaration in stable field order.
The Issue Browser decoder port consumes an explicit `record<HttpResponse>` and
produces `record<IssuePage>`. Native and JavaScript validation agree on response
status, JSON shape, unique IDs in the JavaScript safe-integer range, string
titles, and pagination metadata. The browser decoder preserves JSON number
lexemes before ordinary parsing so fractional values cannot round into accepted
integer IDs; paired native/JavaScript fixtures include exponents, decimal forms,
precision boundaries, and the maximum safe ID. The reducer checks uniqueness
again after cross-page concatenation before committing keyed state.

## Evidence and remaining TCB

The test-owned native command interpreter covers every `Cmd` constructor with
deterministic storage, HTTP, foreign, batch, cancellation, and timeout behavior.
Pure Notes and Issue Browser tests cover restore/debounce/error, independent
restore/save failures, stale results, pagination, duplicate-key rejection, retry,
and disposal. Native-derived artifacts expose representative status transitions
that Chromium consumes. Fake-host JavaScript tests cover fulfilled and hostile
rejected promises, same-handle replacement, missing ports, explicit/reentrant/
throwing cancellation, rejected cancel promises, abort, delivery failure, and
disposal without unhandled rejection. Blocked Web Storage acquisition becomes a
visible restore error rather than aborting mount. Generated artifacts are byte-deterministic;
Chromium exercises public Notes and Issue Browser applications with hostile text,
duplicate page data, and accessibility assertions.

These gates do not constitute a formal proof of command extraction or browser
behavior. Specialized backend state-machine agreement, JavaScript array/object
layouts, event adapters, promise ordering, platform timer/storage/fetch/abort,
the explicit decoder module, the JavaScript engine, and DOM remain in the TCB.
