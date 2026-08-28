# Dogfood log

## M0 tooling smoke

### Scenario exercised

Pinned-toolchain Lake build and a public-library import from the native test
executable.

### What was pleasant

The required Lean 4.33.0 toolchain was already present, so the baseline required
no network fetch and produced a small dependency-free manifest.

### Friction

A module documentation comment cannot directly annotate a namespace in Lean
4.33.0; using a module comment fixed the root module cleanly. pnpm is not
available, but JavaScript tooling is intentionally deferred until M3.

### Missing framework capability

All user-facing framework capabilities are intentionally absent in M0.

### Bugs found

The initial root comment form caused a parser error. It was corrected before the
bootstrap commit; the native smoke executable covers import and version access.

### Performance observations

The dependency-free clean build completed in under three seconds on the baseline
machine. This is a tooling observation, not a framework benchmark.

### Follow-up issue or commit

`14d44a6 chore(repo): initialize LeanRx Lake package`

## Expression Playground

### Scenario exercised

Typed `price`, `quantity`, and `threshold` fields; staged `subtotal`, `isLarge`,
and conditional `label` expressions; dependency inspection; and native evaluation
against two heterogeneous stores.

### What was pleasant

Typed field witnesses make cross-typed reads unrepresentable, and expression
dependencies are inspectable through the same public values used for evaluation.
The output is deterministic enough to gate as a small golden fixture.

### Friction

The explicit combinators are intentionally verbose. There is no local staged
`let` or operator notation yet, so nested arithmetic is noisier than ordinary Lean.

### Missing framework capability

No source syntax, components, updates, graph extraction, or browser lowering is
expected in M1. Formatting values into staged strings is still primitive.

### Bugs found

Generalizing schema/store universes exposed several accidentally universe-zero
helper signatures; store integration tests forced those signatures to be fixed.

### Performance observations

The playground performs full pure evaluation. Runtime propagation work reduction
is an M2/M5 measurement and is not claimed here.

### Follow-up issue or commit

`example(expr): dogfood the scalar expression core`

## Graph Lab

### Scenario exercised

A public-API diamond graph with stable IDs, direct edges, certified topological
ranks, full-recomputation and actual-change evaluation, plus the required parity
case where `count` changes from 1 to 3 while `parity` remains odd.

### What was pleasant

Graph planning, deterministic artifact generation, reference evaluation, and
optimized evaluation are independently callable pure APIs. The diamond output is
compact enough for an exact golden, and the parity case makes work suppression
visible without browser instrumentation.

### Friction

The first Graph Lab version declared executable graph metadata and homogeneous
proof evaluators separately. Independent M2 review rejected that drift risk. The
all-`Int` proof subset now declares staged `RxExpr` values once and derives both
the planned graph and abstract program through `Graph.planInt`; general
heterogeneous component extraction remains future work.

### Missing framework capability

There is no source component syntax, automatic graph extraction from `RxExpr`,
JavaScript lowering, browser host, or DOM sink yet. Those begin in M3–M5.

### Bugs found

The first fixture review showed that graph validation allowed another node to
depend on a sink. `LRX-GRAPH-012` now rejects that invalid scalar-graph shape, and
the case is a permanent regression test. A later review found that validated
planned graphs were forgeable and Graph Lab duplicated its semantic program;
private planned constructors, a checked typed bridge, and compile-fail/connection
tests now cover both defects.

### Performance observations

For `count 1 → 3`, full recomputation performs two derived and two sink
evaluations. Actual-change propagation evaluates parity once and performs no
downstream or sink work: four evaluations versus one. This is deterministic work
instrumentation, not a wall-clock benchmark.

### Follow-up issue or commit

`example(graph): add native propagation laboratory`

## Expression Playground — generated ESM

### Scenario exercised

The existing public `subtotal`, `isLarge`, and conditional `label` expressions
are compiled through `RxExpr → Reactive IR → validated JavaScript AST → ESM`,
imported under Node, and compared with native Lean results for both playground
stores.

### What was pleasant

The compiler phases remain independently callable pure functions. The example
generator performs only file orchestration, and the Node runner needs no Lean
runtime or third-party package. Each module now carries deterministic ABI metadata
that the public dogfood reads and checks before execution.

### Friction

M3 has no component command or build CLI yet, so the dogfood uses a test-only
output-directory harness. Each generated evaluator currently accepts the whole
schema parameter list, including fields that a particular expression does not
read; later lowering can specialize parameters from the dependency index.

### Missing framework capability

There is still no DOM, event, component, or browser host output. The ESM functions
are pure scalar evaluators only, as required for M3.

### Bugs found

The differential gate found that the first `Int.mod` helper normalized with the
signed divisor. For `7 % -5`, Lean returned `2` while generated JavaScript returned
`-3`. The helper now normalizes with the absolute divisor, and all signed/zero
cases are permanent regressions. Independent review also found missing strict-ESM
identifier exclusions, shallow AST binding validation, and an untyped IR input
boundary; hostile-name Node imports, negative AST fixtures, and signature mismatch
tests now preserve those fixes.

### Performance observations

The gate records deterministic bytes and semantic results, not wall-clock
performance. No benchmark claim is made before the correctness baseline closes.

### Follow-up issue or commit

`example(js): emit and run the expression playground`

## Counter — direct DOM component

### Scenario exercised

One `Int` state field, `doubled` and `parity` derived values, four click events,
five scalar text sinks (including hostile generated text), deterministic graph/ESM/manifest output, two independent
mounts, and idempotent disposal in real Chromium. The example imports only the
public `LeanRx` root. Its browser artifact is generated through the scoped
`component` command and JSX-like view, while the same declarations also exercise
the explicit component/view API directly.

### What was pleasant

The same dependency-indexed expressions supply native typing, graph edges,
JavaScript evaluators, initial DOM text, and update functions. Generated event
functions own state changes, derived order, equality checks, and sink guards; the
handwritten host remains limited to DOM calls, listener bridging, and cleanup.

### Friction

The M4 command deliberately keeps declaration right-hand sides as explicit
checked terms, and balanced `[...]` JSX children are slightly noisier than paired
HTML closing tags. Evaluators currently accept every component
value as a parameter. M4 initially recomputed every derived value before
suppressing unchanged sinks; M5 replaced that conservative pass with a generated
direct-dependency frontier in certified rank order.

### Missing framework capability

The M4 CLI resolves the registered `Examples.Counter` module; general module
discovery waits for the production module registry. Dynamic structure, properties
beyond the static M4 whitelist, and non-click event payloads remain intentionally
unsupported.

### Bugs found

The first axe run rejected Counter because the page had no level-one heading.
Adding a real `<h1>` to the public view fixed the defect and made the automated
scan a permanent browser gate. An early hostile-text test called the DOM host
directly and therefore bypassed component lowering; moving it into Counter's
public `scalarText` view made the full Component → JavaScript AST → browser path
the permanent regression and demonstrates that `<img ... onerror>` remains a text node.
The first CLI publisher moved the old directory aside before renaming the new
one, leaving a brief absent-path window. Counter's CLI regression now publishes
locked versioned siblings through one pointer rename and rejects unmanaged
destinations rather than pretending their replacement is atomic.

### Security and accessibility checks

Chromium verifies native buttons in source order, keyboard `Tab` focus and
`Enter` activation, `type="button"`, listener removal, hostile text, and zero axe
violations. Manual review confirms a single descriptive `<h1>`, a `<main>`
landmark, visible button labels, and logical focus order. Form labels and live
error regions are not applicable to this Counter.

### Performance observations

For `addTwo` from 1 to 3, the parity evaluator returns `"odd"` again and the
generated changed frontier performs zero parity text writes, observed with a
`MutationObserver`. M5 instrumentation makes the stronger behavior visible: two
source writes produce one commit, two derived evaluations, one derived change,
three sink evaluations, and two DOM writes; the parity sink never evaluates and
the dependency-bearing stable-text sink evaluates without writing its equal cache.

### Follow-up issue or commit

`feat(backend): emit component mount and dispose`

## Diamond Lab — transaction fan-in

### Scenario exercised

One batched event writes `count` twice. Rank-one `left` and `right` feed the
rank-two `total`, with three direct text sinks. The same dependency-indexed
expressions construct both the browser component and the all-`Int` abstract
reference/optimized programs.

### Findings

The public API was sufficient for the diamond without a handwritten scheduler.
Chromium observes only `Total: 19`, never a mixed-parent intermediate value, and
the total text node mutates once. Per-mount instrumentation records one commit,
two source writes, three derived evaluations/changes, three sink evaluations,
and three DOM writes. The trace orders `left`, `right`, then `total`, and starts
all sinks after the fan-in derived node.

The native expected artifact and optimized model agree on final total `19`; it is
generated beside the browser module and checked in the browser gate. A 1,000-step
alternating small-diamond smoke benchmark recorded 3,000 derived and 1,000 sink
evaluations. The same gate records the parity actual-change case at four reference
evaluations versus one optimized evaluation. Elapsed nanoseconds are printed for
reproducibility but are not a CI performance threshold.

On the 2026-08-19 local debug build, that smoke run reported 1,559,792 ns for the
1,000-update loop. This is an environment-specific observation, not a comparative
benchmark; ADR-0009 reserves the complete size/build/mount/update/DOM/memory
report for M10.

### Follow-up issue or commit

`example(diamond): add fan-in propagation lab`

## Dependent Tabs — indexed props and selection

### Scenario exercised

The public `TabsSpec` API receives equal `Vector String (n + 1)` label and panel
props, stores selection as `Fin (n + 1)`, and exposes one typed `select` event
whose payload is definitionally identical to its state target. The three-tab
dogfood starts on the second panel, lowers selection through
`RxExpr.vectorGet → Reactive IR → validated JavaScript AST`, and generates one
private event forwarder for each finite vector index.

### What was pleasant

Length equality, nonemptiness, initial selection, safe panel access, and event
assignment compatibility are visible in ordinary Lean types. The example file
imports only `LeanRx`; no application code describes graph edges, JavaScript, a
scheduler, or DOM mutation. Chromium can click every generated button and never
observe an absent panel, while the emitted evaluator remains the compact
`panels[selected]` operation.

### Friction

Pinned Lean's standard numeric literal instance for `Fin` normalizes modulo:
`(3 : Fin 3).val == 0`. The original compile-fail assumption was therefore
false. ADR-0011 records the reproduction and changes the public initial-selection
API to `createAt index proof`, retaining `Fin` internally without silently losing
out-of-range intent. Indexed APIs also produce universe-level values that must be
pattern-matched rather than monadically rebound inside `IO Unit` tests.

### Missing framework capability

M6 immutable props are compiler-known values embedded in the artifact; a
general checked mount-time prop decoder is not yet exposed. Tabs uses a named
native-button group with maintained `aria-pressed` state instead of claiming a
complete ARIA tabs/arrow-key widget.
Dynamic keyed collections and foreign/untrusted value validation belong to later
milestones.

### Bugs found

The first generated root was a `div`; axe reported missing main-landmark and
region violations. Emitting a semantic `main` fixed both and is now covered by
the browser gate. The false `Fin` literal assumption became a permanent native
premise test, compile-fail boundary, and ADR rather than a fake negative fixture.

### Security and accessibility checks

Only `mount` is exported; the typed event function is private. Artifact checks
reject serialized proof markers, Lean `Fin`/`Vector` runtime names, dynamic-code
constructs, Proxy discovery, and any fourth handler for the three-tab fixture.
Chromium verifies initial selection, all three click paths, native-button
`Tab`/`Enter` activation, maintained `aria-pressed` state, exact label/panel
alignment, hostile name/label/panel text, and zero axe violations.
The defining interaction snapshot records four selections as four source writes,
three sink evaluations, one direct text write, and four commits, with stable
event/source/sink/DOM/commit trace entries.

### Performance observations

Each changed selection performs one array read and at most one direct text-node
assignment. Reselecting the active tab performs zero sink evaluations and zero
DOM writes; equal panel output is also guarded by a sink cache. This is structural
evidence from generated code, not an M10 wall-clock or memory benchmark. Vector
lengths and `Fin` proofs do not appear as runtime objects.

### Follow-up issue or commit

`example(tabs): dogfood dependent selection`

## Temperature Converter — controlled typed input

### Scenario exercised

Two raw `String` sources receive typed `input` payloads; a compiler-owned `Bool`
source records the active edited scale. Editing Celsius parses
and converts only into Fahrenheit; editing Fahrenheit does the inverse, so there
is no derived cycle. Each checked event plan explicitly records its edited,
active-scale, and conditional opposite-source write; the checked graph records
both property sinks, the parse-error sink, and invalid-state sinks. Invalid raw
text remains in the edited control, leaves the
other value unchanged, and renders an explicit parse error. Native Lean produces
the browser fixture's expected results, including a value above 2^53.

### What was pleasant

The public model makes both event payload/target pairs inspectable and the graph
shows two independent rank-zero sources rather than a fragile two-way derived
cycle. The generated handler never writes the input currently being edited, so
the browser preserves the exact cursor position while still controlling external
updates to the opposite field.

### Friction

The first parser intentionally accepts signed integer text only. This keeps Lean
`Int.tdiv` and JavaScript BigInt division exactly aligned, but it is less friendly
than decimal/locale-aware temperature entry. Adding decimals needs an explicit
numeric representation and differential contract, not a permissive `Number()`
shortcut.

### Bugs found

The first handler draft installed the invalid message before testing valid input,
then cleared it in the valid branch. It would have produced two unnecessary text
writes for every successful edit. Splitting the valid/invalid branches removed
that transient work. Independent review then found that
Lean's standard integer parsers accept digit separators while the compiler-owned
browser regex does not. Native parsing now enforces the same closed ASCII grammar
first, with `1_000` and `-0_1` locked as native/browser rejections.
Review also found that the backend's opposite-source write and error work were
missing from the checked model, and that form work had reused the derived counter
slots despite a zero-derived manifest. Checked update metadata, complete sink
nodes, shared typed DOM lowering, and the original instrumentation meanings now
make those contracts inspectable rather than backend convention.
An adversarial two-order scenario then exposed hidden last-event state: identical
raw strings could render different invalid observations. `activeCelsius` is now
an explicit source, both invalid sinks parse their own raw values, and two event
orders that converge on the same complete store render identically.

### Security and accessibility checks

Labels wrap their controls; both inputs describe the shared live error and
maintain independently parsed `aria-invalid`, and axe is green. A two-order
browser regression covers simultaneous invalid values. A hostile
`<img ... onerror>` string remains the input
property value, creates no element, and executes nothing. Generated parsing uses
only a compiler-owned regex literal followed by BigInt after the lexical guard;
no exception path, `eval`, `Function`, Proxy, or handwritten reactive JavaScript
appears.

### Performance observations

Nine input events record nine commits, twenty-four source-write evaluations (nine
raw edits, nine active-scale writes, and six successful conversion writes), zero
derived work, forty-two sink
evaluations, and ten guarded property/error/invalid-state DOM writes. These are
deterministic work counters, not a speed benchmark.

### Follow-up issue or commit

`example(temperature): dogfood controlled conversion`

## Validated Form — refinement and submit capability

### Scenario exercised

Name, age, and accepted-terms sources use typed text/text/checked payloads.
Validation accumulates a nonempty-name error, bounded-natural error, and required
acceptance error. A submit button's `disabled` property follows validity, but the
generated submit handler independently revalidates before constructing the fake
command. Keydown, focus, blur, change, and prevented submit payload adapters all
run through the public closed event model. Name and submit-authoritative age state
use `input`; an observational age listener exercises text `change`; terms uses
checked `change`, so each closed adapter reaches production lowering without a
stale-state window.

### What was pleasant

`ValidatedForm` has a private constructor, so application/native code can call
`submit` only from the `.valid` branch. The fake command payload therefore needs
no optional fields or defensive defaults. The same expected payload is generated
by native Lean and observed in Chromium after a synthetic invalid submit,
demonstrating that disabled-button state is not the sole guard.

### Friction

Indexed/refined values are excellent at the command boundary but more verbose in
tests because valid and invalid branches must be handled explicitly. The browser
backend still duplicates the closed validation algorithm and remains in the TCB;
native fixtures and exact messages detect drift, but do not constitute a proof of
the JavaScript implementation. A real asynchronous `Cmd` begins in M9.

### Bugs found

The first generated live error strings were generic and did not match native
validator messages. Dogfood made that drift visible; the generated ASCII trim,
parse, lower-bound, upper-bound, and acceptance branches now emit the exact native
messages. A browser case for `1_0` now distinguishes the shared closed natural
grammar from Lean's separator-accepting standard parser. A later adversarial API
check found that the fake command structure was
still directly constructible even though `ValidatedForm` was private; its
constructor is now private and permanently compile-fail gated. The accessibility
test also initially kept two full `main` components
mounted while scanning the page; it now verifies cross-instance ID uniqueness,
disposes the second instance, then runs axe on a valid one-main document.
Review further found raw key payloads retained in the cumulative trace and form
validation counted as derived work. Traces now expose only the stable
`payload:key` category; zero-derived manifests keep derived counters at zero,
while sink evaluation and DOM-write counters measure their documented work.
Review also reproduced a valid-to-visible-invalid submit before blur when age was
authoritative only on `change`. Age now synchronizes on `input`, the no-blur
submit is rejected, and dependency-filtered rendering evaluates only the changed
field's error plus the shared disabled sink during ordinary edits. The initial
checkbox `aria-invalid` state was also missing in the first generated mount and
is now asserted before any event.

### Security and accessibility checks

Every text control has a unique generated ID, matching label, described error,
and maintained `aria-invalid`; errors are live regions and submission status uses
`role="status"`. Chromium verifies checked/disabled properties, keyboard/focus/
blur traces, Enter submit prevention, zero invalid commands, hostile trimmed name
text, native-matched lexical and upper-bound errors, valid-to-invalid submit
rejection, unique IDs and isolation across two mounts, post-disposal listener
removal, and zero axe violations. Only `mount` is
exported.

### Performance observations

The defining path records eight commits (two rejected submits, five source edits,
and one valid submit), five source writes, zero derived work, twenty-three sink
evaluations, and twelve guarded text/property/attribute writes including final
status. This is work instrumentation, not a throughput claim.

### Follow-up issue or commit

`example(form): dogfood validated submission`

## TodoMVC — local conditional, positional, and keyed regions

### Scenario exercised

TodoMVC creates hostile and ordinary titles, toggles completion, switches
all/active/completed filters, enters and commits local editing state, reverses row order,
deletes a keyed row, and clears completed items. A pure `Todo.update` model and
native expected artifact drive the generated-browser logical DOM comparison.
Only public LeanRx/Todo APIs declare the application; there is no handwritten
reactive JavaScript in the example.

### What was pleasant

Opaque region tokens made the identity contract testable before DOM work. The
browser then retained the exact second-row node through filtering and reorder,
retained its edit input and focus during a programmatic reorder, and routed Enter
to the correct key afterward. Stable view branches use direct checkbox/text
updates; only edit/view transitions replace branch shape. The root identity never
changes, and one completion toggle produces zero child-list mutations.

### Friction

The first dynamic backend is intentionally explicit and therefore verbose: the
typed JavaScript AST gained only `for…of`, while row/filter/branch creation stays
as validated AST rather than an opaque template string. Delegated events need
compiler-owned action/key attributes and a documented fixed payload. The
specialized Todo array ABI is clear but is not yet a reusable derived record
lowering. Child component ownership was not needed because each row owns only a
conditional region and delegated events.

### Bugs found

The first click path would have rendered a checkbox's old state before its
subsequent `change` event; unknown click actions now return without propagation.
The backend initially cleared editing unconditionally during `clearCompleted`,
unlike the pure model, and was corrected to retain an active edited item. Initial
instrumentation also reused depth/DOM slots for render/event counts; standard
indices are restored and local structural metrics are exposed separately. The
browser identity assertion originally compared automation handles rather than
in-page nodes, so it now checks actual DOM object identity.
An independent differential review then found the inverse edge case: the native
model replaced a surviving unsaved draft while the generated backend retained
it. Both now preserve that draft, with native and Chromium regressions. The same
review found stale-token forgery in the public reference reconciler API, so only
private-constructor result states can be reconciled. Browser review caught
unscoped delegated Enter/Escape handling, an unlabeled dynamic checkbox, and a
clickable non-control title span; the key path is input-only, checkbox names are
maintained from safe title text, and only native controls carry actions. Backend
review also found that toggle lowering trusted the browser's `checked` payload
instead of implementing the closed native `Msg.toggle` operation, and that a
nested title assignment was absent from source-write instrumentation. Generated
toggle now negates stored state, an adversarial unchanged-property event
distinguishes that behavior, and a focused nonempty-save assertion locks all four
evaluated writes.

### Security and accessibility checks

Titles always enter text nodes; a hostile `<img ... onerror>` title creates no
element and executes nothing. Delegation searches only the fixed
`data-lrx-action` marker inside its registered root. Inputs have programmatic
names, controls are native buttons/checkboxes, filter state uses `aria-pressed`,
the list and filters are named, status is live, keyboard add/edit commit works,
and axe is green.

### Performance observations

The defining scenario records the standard snapshot
`[0,17,26,0,0,39,203]`: zero depth/derived work, seventeen commits,
twenty-six evaluated state writes, thirty-nine region/status sink
evaluations, and 203 compiler-emitted text/property/attribute host writes. The
keyed region records `[4,15,5,4]` mounts/updates/moves/disposals; the
positional filter region records `[3,39,0]`. These are deterministic work counts,
not a timing benchmark. Root/row/input identity and zero child-list work for one
toggle provide the important structural evidence.

### Follow-up issue or commit

`example(todo): dogfood keyed dynamic regions`

## Notes — debounced owned persistence

### Scenario exercised

Notes restores a value from local storage on mount, accepts controlled text
edits, cancels and replaces a 250 ms debounce timer, writes only the final edit,
surfaces storage failures, ignores a late restore after a local edit, and cancels
owned restore/timer/storage work on disposal. The application imports only
public LeanRx APIs; generated handlers consume the pure `Notes.update` lifecycle
through the typed-JavaScript-AST backend and the explicit effect host.

### What was pleasant

Command handles made restore, debounce, save, and disposal races explicit in the
pure reducer before browser work. The same cancellation vocabulary maps directly
to timer IDs, fetch abort controllers, and foreign cancel callbacks without
putting scheduling in the DOM host. Passing state/context explicitly to effect
callbacks kept generated JavaScript first-order and validity-checkable.

### Friction

The current backend is specialized because extracting arbitrary Lean callback
closures would cross the controlled Reactive IR boundary. Command constructors
remain typed public data, while the Notes emitter recognizes this checked
application model explicitly. Browser error objects and storage missing/found
values use a versioned tagged adapter ABI that remains inside the TCB.

### Bugs found

The first pure model allowed a late restore to overwrite text edited while the
storage read was pending. Editing now cancels the restore resource and transitions
it out of loading, with native and Chromium regressions. Runtime prototyping also
showed that single-argument promise callbacks would require generated closures;
the host now delivers explicit state, context, handle, and typed result values.
Independent review found that the first emitter shared one error slot between
restore and save: a new edit retained a stale save failure, while a later save
could erase a restore failure that the pure reducer retained. Restore and save
errors now have independent slots and native-derived status artifacts drive the
browser assertions. The same review caught cancellation calls occurring before
state/render; generated handlers now finish the pure phase before interpreting
the ordered cancel-and-start command batch.

### Security and accessibility checks

The hostile component title is emitted through a text node and creates no image
or handler execution. The textarea has a programmatic name, persistence status is
a polite status region, axe is green, storage/query values never become code or
HTML, all promise rejections become error results, and post-disposal delivery is
suppressed.

### Performance observations

The defining successful restore-plus-two-edit scenario starts four commands
(restore, two timers, one storage write), cancels the first timer, and persists
only the final draft. These are deterministic work counts, not a latency claim;
the browser test waits relative to the native-derived 250 ms debounce artifact.

### Follow-up issue or commit

`example(notes): dogfood owned persistence`

## Issue Browser — cancellable HTTP resources and typed decoding

### Scenario exercised

Issue Browser starts a real loopback HTTP request on mount, repeats it from a
keyboard-activated Search button, appends a second page through a keyed region,
shows typed decoder and non-200 failures, retries the last request, and replaces
a delayed query with a newer one. A query containing `&`, `=`, and `?` reaches
the server as one exact query value. Disposal while another delayed request is
owned aborts it and suppresses all later delivery. The example imports only the
public LeanRx API; the native reducer produces the initial request/decoder oracle.

### What was pleasant

The same opaque command handle drives pure stale-result rejection, runtime
ownership, `AbortController`, and disposal. HTTP query pairs remain structured
until the effect adapter applies `URLSearchParams`, so application/backend code
never concatenates untrusted URLs. The decoder is an explicit checked foreign
port with a native mock and a deterministic manifest disclosure of its wire
types, errors, trust boundary, and security behavior.

### Friction

Structured JSON results cannot honestly reuse the scalar reactive
`RuntimeTypeId`: doing so would reopen equality and lowering contracts sealed in
M1. A separate manifest/port-only `PortTypeId` was required. The specialized
backend still duplicates the pure Issue Browser state machine and the browser
JSON decoder; native artifacts and adversarial browser cases detect drift, but
that agreement is executable evidence rather than a proof of JavaScript or DOM
behavior.

### Bugs found

The first foreign-port draft assumed every input and output had a scalar runtime
representation, which could not describe `IssuePage` without weakening the
reactive ABI. Structured wire metadata is now isolated from reactive equality,
and type-indexed `PortRep` evidence plus nominal wrappers prevent mismatched wire
metadata. The generated manifest now locks the exact response-to-page decoder
contract. Independent review also found native/JavaScript safe-ID drift,
same-page and cross-page duplicate keys, stale completion after numeric-handle
reuse, reentrant/throwing cancellation, and partial cleanup after a cancel throw.
Review then sharpened those cases: lossy `JSON.parse` numbers admitted fractional
IDs that rounded to integers, reentrant replacement could orphan a nested
same-handle command, and eagerly reading blocked Web Storage could abort mount.
The decoder now preserves number lexemes, replacement installs an ownership
reservation before cancellation, and storage acquisition occurs inside the
owned error path. A follow-up native counterexample found that enormous zero
exponents could consume seconds or panic inside Lean's general JSON parser; both
ports now reject exponent magnitudes above 16 before parsing. Exact native,
fake-host, and Chromium regressions cover these
contracts. Ownership is removed before cancellation, completion is bound to its
exact entry, and cleanup failures are normalized without skipping the base disposer.

### Security and accessibility checks

Hostile component and issue titles stay in text nodes and create no image or
handler execution. Query punctuation is encoded by the owned HTTP adapter.
Decoder validation rejects malformed arrays, unsafe/non-natural IDs, and
non-string titles before they reach the region. The query input and issue list
have programmatic names, all actions are native buttons, loading/error output is
a live status, Search is exercised by keyboard, populated content passes axe,
and no promise rejection reaches the page.

### Performance observations

The defining scenario records the exact effect snapshot `[13,2]`: thirteen HTTP
commands start, one delayed request is cancelled by a newer query, and one is
cancelled by component disposal. The additional requests exercise same-page and
cross-page duplicate rejection without committing invalid keyed state.
Pagination retains the first keyed issue and mounts only the new page. These are
deterministic ownership/work counters, not a network throughput claim.

### Follow-up issue or commit

`example(issue): dogfood cancellable HTTP resources`

## Data Grid — 10k structural strategy experiment

### Scenario exercised

The public `Grid.Spec` fixes one 10,000-row application and the defining create,
single-row update, every-tenth removal, two-row swap, odd filter, descending sort,
and keyed selection sequence. The generated module exports full keyed, explicit
checked-delta, and hybrid-cost-model mounts. Every strategy begins at the checked
empty state and runs those seven actions. The browser compares all 5,000 final
keys, text values, order positions, and selection bits with the native
`Grid.visibleRows` oracle, while
intermediate assertions make every operation branch-effective. No application
handwritten reactivity bypasses the public API.

### What was pleasant

The proof-carrying delta planner made fallback explicit: a candidate batch either
replays to the independently recomputed target or becomes one visible reset.
This kept pure correctness independent of the empirical cost model. The same
mount/update/dispose row callbacks drive full and delta region hosts, so the
browser comparison retains identical text, keyed identity, disposal, hostile
content, and accessibility semantics. Copied instrumentation clearly separates
standard transaction/sink/DOM work from structural operations and Grid-specific
projection/search/scan work.

### Friction

The specialized typed-JavaScript-AST emitter is large because arbitrary Lean
reducers are still outside the controlled backend. Delta filtering and sorting
fall back to reset; they do not yet compose verified `filterDelta`/`sortDelta`
operators. The first cost model undercounts generated validation/projection work:
native modeled derived work falls under delta while generated key-search and
validation costs rise. The checked generated component therefore fixes one
concrete default cost model; alternate models remain pure-runner research inputs.
Sampled browser allocations vary by run and process-wide heap reporting is too
coarse to distinguish strategies. The full experiment adds a material
API/runtime/test burden for workload-dependent wins.

### Bugs found

Initial lowering indexed the row array and search index in the wrong order; JS
AST validation exposed the failing function but its generic message omitted the
name, so the diagnostic and its regression now identify the invalid scope.
Independent review found and regressed several deeper contract errors: reverse
was not descending sort; accepted cost fields were ignored by the backend;
same-key swap corrupted a neighbor; Update after removal threw a raw JavaScript
error; the generated mount skipped the checked empty state; final endpoint-only
comparison hid interior drift; and standard instrumentation confused transaction
depth, structural visits, sink evaluations, and DOM writes. Sealed state/spec/
planned-delta boundaries, full native-oracle comparison, invalid-action guards,
manifest ABI assertions, and exact copied snapshots now lock those fixes.

The first accessibility pass modeled a read-only result set as an interactive
ARIA grid without implementing composite keyboard navigation. The final UI uses
a named read-only table with row/cell structure and an external named group of
native action buttons. Running the 10k workload in the same long-lived Chromium
process also made unrelated tests order-dependent under GC pressure; the focused
grid gate therefore receives a fresh browser process after the standard suite.
The disposer host also now clears listener-remover closures so retaining copied
metrics cannot retain the 10k source arrays after disposal.

### Security and accessibility checks

The hostile component name stays literal text and creates no image or handler.
All action markers are native buttons; the table, status, and operation group are
programmatically named. Each row contains one cell, the selected read-only row
uses `aria-current`, and the populated representative accessibility scan is
green. Row-dependent controls are disabled before Create, Update remains disabled
after its key is removed, and native keyboard activation exercises Create.
Repeated selection performs no derived, DOM, or region work. Disposal is
idempotent and a detached control cannot change copied instrumentation.

### Performance observations

Five native samples show effectively tied median trace time despite deterministic
work differences. Six position-balanced Chromium samples show large small-update,
reorder, and selection improvements for delta/hybrid, but explicit delta loses on
bulk removal and does not improve filtering or sorting. Full/delta/hybrid perform
43,007/10,009/19,009 standard sink evaluations and 43,000/10,002/19,002 retained
updates, while every strategy performs exactly 40,009 emitted DOM writes.
Modeled native allocation units are 53,000/20,002/29,002; sampled V8 allocation
medians are about 2.10/2.17/2.23 MB and are observational, not thresholds. Exact
commands, operation medians, work counts, artifact sizes, clean build time,
complexity, and limitations are recorded in
`docs/performance/m10-data-grid.md`.

### Follow-up issue or commit

`docs(delta): keep structural deltas opt-in`

## LeanRx documentation site — self-hosting and learnability

### Scenario exercised

The public component API builds a seven-page documentation application covering
the introduction, Counter, static graphs, dependent Tabs, effects/resources,
limitations, and a generated graph viewer. One checked page source drives three
derived text values and three direct text sinks. Seven native buttons traverse
the complete defining scenario, and the build atomically publishes its module,
manifest, JSON/DOT/script-free HTML graphs, editor declarations, production HTML
shell, stylesheet, and the two required host modules. No application handwritten
reactivity or another frontend framework sits between the component and browser.

### What was pleasant

Static page selection is ordinary dependency-indexed scalar code, so all content
changes have an explicit graph and deterministic work trace. The docs component's
checked graph feeds its CLI output and accessible standalone HTML card viewer;
the embedded inert DOT page deliberately displays Counter's separate public
checked graph. Generated declaration aliases make the syntax-produced schema,
surface inventory, spec, and validation result inspectable in an editor. Atomic
publication and the closed text-node path made a small production-shaped bundle
possible without widening the runtime.

### Friction and missing features

LeanRx has no URL/history router, so page selection is component state and a
reload returns to the introduction. The closed view vocabulary has no semantic
`nav`, links, code/preformatted blocks, lists, sections, or typed CSS capability;
the dogfood therefore uses a `main`, a layout `div`, native buttons, paragraphs,
and a deliberately small external stylesheet. There is no general Virtual DOM,
arbitrary Lean transpiler, raw HTML, URL attribute, SSR, hydration, or formal
proof of the JavaScript/DOM connection. The generated graph viewer is static and
script-free rather than an interactive graph explorer. These boundaries are
shown on the Limitations page instead of being hidden behind another framework.

### Bugs found

The first component surface used `view` as both the declaration keyword and the
local value name, which the scoped macro grammar rejected. Renaming the value to
`docsView` keeps the generated surface unambiguous. The first browser assertion
also applied a strict single-element attribute matcher to all seven buttons;
the permanent regression now checks every button explicitly. No framework
runtime defect was required to complete the site.

### Security and accessibility checks

All navigation actions are native `type=button` controls and keyboard activation
opens Counter. The site has one `main`/`h1` content structure, visible focus, a
responsive layout, and a populated axe scan with zero automated violations.
Hostile Limitations text containing an image/onerror payload stays literal,
creates no element, and executes nothing. The standalone graph HTML contains no
script, generated modules contain no raw-HTML/dynamic-code escape, two mounts are
isolated, and disposal removes listeners idempotently.

### Performance observations

The defining seven-page traversal has the exact standard snapshot
`[0,7,7,21,21,21,21]`: seven outer transactions/source writes, three derived
evaluations and changes per real page change, and three sink evaluations/DOM
writes per page. This is a deterministic work contract, not a latency claim.

### Follow-up issue or commit

`example(docs): dogfood LeanRx documentation site`

## Expression and view surface — rx%, keyed lists, and nested components

### Scenario exercised

The six expression-bearing examples dropped their hand-written `RxExpr`
constructor trees for the scoped `rx%` surface (`count * 2`,
`if count % 2 == 0 then "even" else "odd"`, `s!"Count: {count}"`), and TodoMVC
was rewritten at the user surface: `examples/TodoMVC.lean` now declares a
nested `TodoRow` component with typed props, the keyed row list through
`for todo in visible model key todo.id => …`, and the full logical view in
`jsx%`. The differential golden projection is generated from that surface, and
the emitted `TodoMVC.mjs` bundle stayed byte-identical.

### What was pleasant

Typeclass-directed smart constructors made `rx%` a thin macro: every staged
tree is the exact tree the explicit API builds, so goldens, dependency sets,
and evaluator names did not move. Selecting the JSX lowering from the expected
type meant one grammar serves both the schema-typed safe view and the logical
region model, and nested components are ordinary typed Lean applications, so a
mistyped prop is a plain Lean type error at the call site. An `ImmutableProp`
prop wraps itself with its attribute name, connecting the M6 props model to
the surface without new machinery.

### Friction

Scoped surface keywords (`state`, `derived`, `event`, `view`, `key`) still
cannot be used as identifiers where `LeanRxDsl` is open; the TodoMVC surface
names its state parameter `model` and its view `todoView`, and the typed test
escapes the `view` structure field as `«view»`. `section` stays out of the tag
whitelist because it is a Lean command keyword. The logical surface carries no
events, so TodoMVC's delegated event wiring remains in the backend rather than
the DSL, and the typed event surface still lacks payloads (`onInput`,
`onKeyDown`) beyond the new `onDblClick`.

### Bugs found

No framework defect: the byte-diff against the previous bundle, the structural
`rx%` equivalence suite, and the extensional TodoMVC surface/reference
comparison across thirteen reducer states all held on the first green build.

### Follow-up issue or commit

`feat(elab): stage ordinary expression syntax with rx% (ADR-0033)` and
`feat(elab): lower one JSX surface into typed views and the logical region
model (ADR-0034)`.

## Component sugar and typed payloads — items, references, and Echo Lab

### Scenario exercised

Counter and DiamondLab rewrote their `component` blocks in the sketched M4
surface — `state count : Int := 1`, `derived doubled := rx% count * 2`,
`event addTwo := set count (count + 1) then set count (count + 1)`,
`dispatch` nesting, inline `rx%` sinks, and `onClick={increment}` reference
bindings — with the generated `Counter.mjs`/`DiamondLab.mjs` byte-identical
to the wrapper-style output. A new Echo Lab example declares typed payload
events (`event setDraft (value : String) := set draft value;`) bound with
`onInput`/`onKeyDown`/`onChange` on inputs beside a payload-less clear
button, lowered through the generic component backend onto the existing
`listenValue`/`listenKey` host adapters, and gated in Chromium
(per-keystroke updates, blur-commit `change`, mixed listeners, disposal).

### What was pleasant

Because the sugar lowers onto the same `ValueSpec`/`EventSpec`/
`TypedEventSpec` values, byte-identity was the acceptance test and it held on
the first diff. Removing the reserved keyword atoms (ADR-0035) turned out to
be a simplification, not a compromise: identifier-led item rules and
name-dispatched attributes reuse the existing diagnostics, and `state`,
`view`, `onClick`, and `id` became ordinary identifiers everywhere. The typed
dispatch functions share the payload-less transaction shell verbatim, so the
commit sweep, instrumentation, and trace vocabulary needed no new runtime.

### Friction

A non-reserved keyword (`&"state"`) cannot lead a syntax-category
alternative — category dispatch never routes an identifier token to it — so
the fix had to be identifier-led rules with elaborator dispatch rather than
Lean's softer keyword flavor. `key` stays reserved because it follows a term
position, and `component` stays a command keyword. The generic typed surface
is one-way (payload to source): reflected DOM properties, `checked`, and
`submit` remain with the bespoke form backends, so a controlled input still
needs those. Typed events must be declared after payload-less events to keep
the surface alignment order.

### Bugs found

No framework defect. The environment audit caught the elaborator rewrite
renaming its generated unsafe helper (`unsafe_1` → `unsafe_5`), which is the
gate working as intended.

### Follow-up issue or commit

`feat(elab): parse surface keywords as plain identifiers (ADR-0035)`,
`feat(elab): sugar component items and bind events by reference (ADR-0036)`,
and `feat(backend): lower typed event payloads through the generic component
backend (ADR-0037)`.

## Controlled inputs and child components — Echo Lab and Nest Lab

### Scenario exercised

Echo Lab became a controlled form through the generic component backend
(ADR-0038): `value={rx% draft}` and `checked={rx% loud}` reflections, a
`type="checkbox"` input with a `Bool` typed event
(`event toggleLoud (checked : Bool) := set loud checked;` bound with
`onCheckedChange`), and a `form onSubmit={saveNote}` whose host adapter owns
`preventDefault`. A new Nest Lab example nests a stateful `<Pulse/>` child
inside `NestLab` (ADR-0039): the parent module imports `mount` from
`./Pulse.mjs`, mounts it mid-tree in document order without a wrapper, and
folds the child disposer into its own. Chromium gates controlled resets,
mid-text cursor preservation, checkbox payloads, prevented submission,
in-order child mounting, state independence, and child disposal.

### What was pleasant

Every host export needed already existed at ABI ≤ 15 — `setProperty`,
`listenChecked`, `listenSubmit` — so the round shipped with no runtime edit
and no ABI bump. Reflected properties turned out to be exactly text sinks
with a property name: the same evaluator table, the same anyChanged guard,
the same cache-compare-write shape, using the previously idle `tx[8]`/`tx[9]`
metric slots. The WHATWG equal-value assignment rule made cursor preservation
free — the cache-guarded write re-assigns the string the user just typed and
the caret provably stays put, which the browser gate pins. Child composition
by module import needed no event namespacing at all: module scope is the
namespace, and mounting `mount(parent)` mid-sequence preserves document order
without a wrapper element.

### Friction

`section` is a Lean keyword, so `<section>` cannot appear in `jsx%` (the tag
was never in the whitelist; `<div class>` stands in). `ComponentSpec` values
live in `Type 1`, so a build driver cannot `←`-bind a `CheckedComponent` in
`IO` and must match instead — same for backend helper tuples, which forced a
small `PropSlot` mirror struct. Widening `typedEvents` to `Bool` payloads
required the closed `AnyTypedEvent` union rather than an array of one payload
type. Child instrumentation is unreachable through the parent disposer, and
transforming reflections legitimately move the caret to the end; both are
recorded as ADR limitations.

### Bugs found

No framework defect. One test bug: focusing an input to keep typing places
the caret at position 0 in Chromium, so the submit gate had to press `End`
first — a useful reminder that controlled-input tests must manage selection
explicitly.

### Follow-up issue or commit

`feat(view): model reflected properties, form submission, and child slots
(ADR-0038, ADR-0039)`, `feat(backend): emit controlled inputs and static
child mounts through the generic component backend`,
`example(echo): make Echo Lab a controlled form`,
`example(nest): nest a stateful Pulse child in Nest Lab`, and
`docs(adr): sketch the App IR generalization of Backend.Todo (ADR-0040)`.

## Keyed regions and immutable props — Nest Lab roster

### Scenario exercised

Nest Lab grew a keyed list written entirely in the `component` command
(ADR-0040 stage 1, ADR-0041): `region roster (label) := jsx% <li> […]`
declares a sealed row template projecting `{label}`, `append roster
(s!"Item {added}")` pushes rows with region-owned monotone keys inside the
ordinary transaction shell, `<region roster/>` mounts the region as the only
child of its `<ul>`, and the per-row `✕` button binds the sealed `remove`
action through one `listenDelegatedCells` listener resolved by row structure.
Pulse simultaneously became a configured child (ADR-0042): `prop title :
String;` plus a `{title}` heading in the child, `<Pulse title="Pulse child"/>`
in the parent, and the value crossing as `mount(target, ["Pulse child"])`.
Chromium gates append order, removal of exactly the dispatching row, key
monotonicity after removal, no-op clicks on row text, prop rendering, and
disposal of region, child, and listeners together.

### What was pleasant

Every host export needed — `createKeyedRegion`, `listenDelegatedCells`,
`setKey` — already existed at ABI 15, so the round again shipped with no
runtime edit. Deciding the row-scope question as a sealed binder (projections
plus a closed action vocabulary) kept `RxExpr`, `DepSet`, and the propagation
proofs completely untouched while still deleting the `data-lrx-action`
pattern: the cell action array falls out of the validated template shape.
Region-owned keys dissolved the uniqueness question — no user key expression
exists, so LRX-REGION-001 holds by construction and the ADR-0027 monotone
fast path is automatic. The dirty-flag commit sweep slotted into the existing
transaction shell after the prop sweep without disturbing any tx slot, and
`makeDisposer`'s long-idle `regions` parameter finally carries generic
handles, exposing region instrumentation for free.

### Friction

The structural-delegation contract (the action element must sit strictly
inside a row cell) is easy to trip over — a `✕` button that *is* the cell
dispatches nothing at runtime — so LRX-VIEW-027 rejects it at compile time
and the guide spells out the required nesting. Two new quasiquote match arms
pushed the single command elaborator past both the elaboration and LCNF
heartbeat budgets; the fix was `getKind` dispatch into helper functions plus
one scoped `set_option maxHeartbeats`. The audit's one-name-per-failure
reporting made registering ~20 new `_unsafe_rec`/`injEq` entries a scripted
loop rather than a single diff. Axe caught an h1→h3 heading skip in the
first Pulse title. `<region roster/>` needed its own grammar alternative
because a lowercase self-closing element otherwise lowers through the closed
tag whitelist.

### Bugs found

One packaging gap rather than a framework defect: the Nest build driver did
not copy `runtime/leanrx_region.mjs` beside the emitted modules, so the first
artifact run failed on module resolution. Byte identity held on the first
try for all eleven non-region dists.

### Follow-up issue or commit

`feat(component): bind keyed regions through sealed row binders (ADR-0040,
ADR-0041)`, `feat(component): pass immutable child props across the mount ABI
(ADR-0042)`, `example(nest): dogfood the keyed roster and the Pulse title
prop`, and the ADR-0040 TodoMVC migration gate list. Remaining gaps carried
forward: row-scope staged expressions (rows stay immutable, projections
only), `disabled` reflection still bespoke-only, transforming reflections
move the caret to the end (documented), and child instrumentation stays
unreachable through the parent disposer.

## Row updates and class selection — marking the Nest Lab roster

### Scenario exercised

The roster rows learned to change after mount, still entirely inside the
`component` command (ADR-0040 stage 2, ADR-0043, ADR-0044): rows widened to
`(label, marks)`, a `row roster mark := set marks (marks ++ " ★");` item
declares the sealed update action, the template renders the sealed row
expression `{label ++ marks}` and selects its root class with
`class={if marks == "" then "roster-row" else "roster-row marked"}`, and the
per-row `★` button dispatches through the same structural delegated listener
as `remove`. An update-only transaction mutates the retained item in place
and drains exactly one `updateAt` on commit; the generated retained-row
callback re-renders the expression text and the class selection by `childAt`
navigation. ADR-0045 records the filter-region decision draft: TodoMVC's
filter row is static view plus future state-scoped attribute selection —
neither a degenerate keyed region nor a new positional slot. Chromium gates
per-row marking (text, class, and an updates-by-exactly-one instrumentation
delta), repeat marking, field retention across removal and append, and the
unchanged stage-1 behaviors.

### What was pleasant

`updateAt`, `childAt`, and the LRX-REGION-003 key re-check all predated the
round — the runtime ABI stayed 15 for the fourth consecutive round, and all
eleven non-region dists stayed byte-identical. Mirroring `RxExpr`'s shape
without touching it worked again one level down: `RowExpr` is three
constructors and a bounds check, yet it serves template text, update
right-hand sides, and (via one sealed predicate) class selection. The
`[cursor, match]` scan array dissolved the "no mutable locals in the
validated JS subset" constraint without extending the AST, and the pending
slot rode the region record without touching `tx` or the context layout.
Deciding the filter question as "not a region" fell out of writing the ADR:
the row set has static cardinality, so both proposed mechanisms encoded
information the static view already knows.

### Friction

`throwErrorAt` parses its string literal as an interpolated string, so the
LRX-ELAB-116 message describing `class={…}` needed `\{` escapes — invisible
until the build broke on a backslash. The update dispatch needs the row's
*position* while delegation hands it the *key*, forcing the linear key scan
in generated code; fine at roster scale, but a future keyed-index handle API
is the obvious escape hatch if a gate ever needs it. The retained-row
callback re-renders unconditionally (bespoke-Todo precedent), which is
correct but means structural reconciles rewrite equal strings; the WHATWG
equal-value rule keeps it observably free. One new grammar rule
(`row region event := …`) again demanded audit re-registration of ten
generated `injEq`/`_unsafe_rec` names — scripted this time from the start.

### Bugs found

No framework defect and no test bug: every gate passed on its first run
after the build went green, including byte identity on the first diff.

### Follow-up issue or commit

`feat(component): update keyed rows through sealed row expressions
(ADR-0043, ADR-0044)`, `example(nest): mark roster rows through the sealed
update action`, `docs(adr): draft the filter-region decision (ADR-0045)`.
Remaining gaps carried forward: conditional structure inside rows, typed
payload row events, state-scoped attribute selection (ADR-0045 confirmation
bar; also closes `disabled`), `s!` interpolation absent from row scope
(`++` only), one class selection per element with a single-field equality
predicate, and child instrumentation still unreachable through the parent
disposer.

## Attribute selection and typed row payloads — Filter Lab and roster editing

### Scenario exercised

Two of the carried gaps closed in one round, both without touching the
runtime. A new Filter Lab example ships ADR-0045's state-scoped attribute
selection: the TodoMVC-shaped filter row is plain static view — three
buttons whose `class` and `aria-pressed` follow
`class={if filter == "all" then "selected" else ""}` /
`ariaPressed={filter == "all"}` sealed selections, plus a Reset button whose
`disabled` property reflects `filter == "all"` — all seven selections
joining the commit sweep beside text sinks and reflected properties with the
evaluate-compare-write shape and appearing as `attr:{i}:{name}` sinks in the
planned graph. Nest Lab's roster rows gained an edit input driven by
ADR-0046 typed row payloads: `row roster rename (value : String) := set
label value;` consumes the delegated `input` value and
`row roster record (pressed : String) := set lastKey ("key:" ++ pressed);`
the delegated `keydown` key, through one `listenDelegatedCells` listener per
bound kind with kind-separated per-cell action arrays. ADR-0047 records the
decision draft for the next gap — conditional row structure (edit input vs
label) as a sealed two-branch row cell.

### What was pleasant

Both features were assembly, not invention. The attribute selection is
exactly a reflected property with a compiler-owned name and a sealed
predicate: the same anyChanged guard, the same cache-compare-write shape,
the same tx[8]/tx[9] counters, and `Field Γ String` in the selection
constructors makes a cross-typed predicate a plain Lean type error before
any validator runs. The `disabled`-as-property decision fell out of the
platform (a `disabled` attribute cannot be cleared by assignment) and
`setProperty` was already imported machinery. On the row side,
`listenDelegatedCells` had been passing `value` and `key` to every dispatch
since ABI 15 — the whole feature was a `RowExpr.payload` constructor, a
`takesPayload` flag, and per-kind action arrays; the browser gate then
showed retained rows keep their input's typed value and caret through the
updateAt re-render for free, because the update callback never navigates to
the input.

### Friction

`key` is a reserved surface keyword (the jsx keyed-list binder), so the
natural `row roster record (key : String)` fails to parse and the parameter
had to be named `pressed`; the guide and LRX-ELAB-117 now spell the
restriction out. The delegated payload class is chosen by the template
binding kind, which forces the bound-exactly-once rule for typed row events
— a declaration-site payload class would lift it but would diverge from the
component-level typed events, which serve both `value` and `key` bindings
from one declaration. Kind-separated action arrays exist because a click
inside the input's cell would otherwise resolve the input's action with a
click payload. Region instrumentation counts a retained-row reposition
during append reconciles as a move, so the typing gate asserts deltas
rather than absolute move counts.

### Bugs found

No framework defect: byte identity held for all eleven non-region dists
(module, manifest, and graph bytes) on the first diff, and every new
browser gate passed on its first run after the parser fix above. The one
test bug was the absolute-move-count assertion corrected to deltas.

### Performance observations

The Filter Lab defining transition (all → active) records exactly seven
selection evaluations and five writes — the Completed button's equal values
and the sweep's cache guard make the difference observable — and
reselecting the active filter records zero selection evaluations, zero DOM
writes, one commit. Each roster keystroke is two transactions (keydown then
input), each draining exactly one retained-row `updateAt` with zero mounts,
moves, or disposals. These are deterministic work counters, not a timing
claim; BENCHMARK.md numbers are untouched by this round.

### Follow-up issue or commit

`feat(component): select state-scoped attributes and typed row payloads
(ADR-0045, ADR-0046)`, `example(filter): dogfood the state-scoped filter
row`, `example(nest): edit roster rows through typed payloads`, and
`docs(adr): draft the sealed row branch cell (ADR-0047)`. Remaining gaps
carried forward: conditional structure inside rows (ADR-0047 confirmation
bar — includes focus transfer and the replace-shaped host call question),
`s!` interpolation absent from row scope (`++` only), attribute selection
limited to one per attribute per element with a single-field `String`
equality predicate, row inputs uncontrolled (no row-field `value`
reflection), and child instrumentation still unreachable through the parent
disposer.

## Conditional row structure — Branch Lab edit/view transition

### Scenario exercised

ADR-0047's confirmation bar closed with the sealed two-branch row cell
shipped through the generic backend and a new Branch Lab example proving
the TodoMVC edit/view transition in Chromium. A task row's first cell is
`{if mode == "view" then <span…/> else <input…/>}`: `RowNode.branch`
carries one row-field index, one comparison literal, and two statically
sealed subtrees, mounts as one wrapper `span` whose rendered branch is the
compiler-owned `$lrxBranch` marker, and the retained-row update callback
updates the stable branch in place or replaces the subtree with one
`detach` plus one `append` of a shared builder function
(`$lrx_region_0_branch_0_t`/`_f`). The edit input reflects `draft` into its
`value` property (the sealed row reflection), so Edit opens pre-filled;
typing flows through the ADR-0046 delegated `input` payload and commit
writes `label := draft` and returns to the view branch. The browser gate
pins branch entry, mid-text typing with a preserved caret, commit with
retained row identity (the same `li` node), draft retention across a
structural reconcile, and update-only region instrumentation for every
step. ADR-0048 records the focus-vocabulary decision draft.

### What was pleasant

The ABI-freeze bar held with room to spare: replacement needed no
`replaceChild` host export because the wrapper cell turns it into
`detach(childAt(cell, 0))` plus `append(cell, fresh)` — `detach` was
already exported by the region host module for its siblings, and the marker
rides the existing `setProperty` export. The ADR-0038 controlled-input
finding transferred to row scope unchanged: because `retype` writes the
delegated payload back into `draft`, the update callback's reflection write
hands the input the string it already holds, and the WHATWG equal-value
assignment left the caret mid-text on the first browser run. The wrapper
also kept every structural invariant for free — one cell, one child index,
`listenDelegatedCells` resolution, and the ADR-0046 action arrays — so the
emitter's only new obligation was the builder-function pair.

### Friction

Static delegated action arrays forced a real design decision on
cross-branch bindings, not just a check: a one-branch `click` binding is
never safe (any content of the other branch bubbles a click into the cell,
including a bare `<span/>` branch root), so clicks must agree exactly and
Branch Lab keeps its Edit/OK/Remove buttons in unbranched cells. That in
turn means the OK button is visible while viewing, and the example carries
the `draft = label` invariant (rows append with both equal, commit restores
it) so the visible OK is a no-op in the view branch — a modeling idiom the
guide now documents rather than a framework guarantee. Validation ordering
also bit once in the model gates: a template that drops a typed event's
binding trips the bound-exactly-once check before the branch shape checks,
so the negative fixtures had to pick their event tables deliberately.

### Bugs found

No framework defect surfaced: the generated module, the four compile-fail
fixtures, and all seven Branch Lab browser tests (including the caret and
identity pins) passed on their first run. The one example-design defect was
caught before any gate ran — the initial draft appended rows with an empty
`draft`, so OK in view mode would have wiped the label; the `draft = label`
append invariant replaced it.

### Performance observations

Entering, typing in, and leaving the edit branch are each exactly one
retained-row `updateAt` with zero region mounts, moves, or disposals — the
branch swap is invisible to the region host by construction. Components
without branch cells emit byte-identical modules, manifests, and graphs
(runtimeAbi stays 15 and the codegen gate re-diffs every dist), and the
js-framework-benchmark path is untouched, so BENCHMARK.md numbers carry
forward unchanged under the performance freeze.

### Follow-up issue or commit

`feat(component): select conditional row structure through sealed branch
cells (ADR-0047)`, `example(branch): prove the edit/view transition in
Branch Lab`, `test(component): forge the branch and reflection gates and
teach the guide`, and `docs(adr): accept the branch cell and draft the row
focus vocabulary (ADR-0047, ADR-0048)`. Remaining gaps carried forward:
focus transfer into fresh edit inputs (ADR-0048 decision draft — `focus`
host export under a future ABI 16), `s!` interpolation absent from row
scope (`++` only), attribute selection limited to one per attribute per
element with a single-field `String` equality predicate, branch cells
single-level and two-branch only with exact click agreement, and child
instrumentation still unreachable through the parent disposer.

## Row focus vocabulary — Branch Lab keyboard-first edit entry

### Scenario exercised

ADR-0048's confirmation bar closed with the sealed `autoFocus` marker and
the `focus(node)` DOM-host export shipped under runtime ABI 16. Branch
Lab's edit input became `<input … value={draft} onInput={retype}
autoFocus/>`: the bare marker is the first inhabitant of the surface
grammar's bare-identifier attribute shape, lowers to one compiler-owned
flag on the sealed row element, and is validated like `value={…}` one rule
further in — inputs only, branch subtrees only, at most one per subtree
(`LRX-VIEW-036`, with three compile-fail fixtures and outright rejection in
the typed and logical views). The update callback's replacement arm — and
only that arm — calls `focus` on the incoming branch's marked input after
`append`, guarded by the same `want` flag that selected the builder. Two
new Chromium gates prove both directions on top of the seven retained
branch gates: clicking Edit focuses the fresh editor with the reflected
draft and typing proceeds keyboard-first, while adding rows keeps focus on
the Add button, commit keeps it on the OK button, and removing a row above
an editing row does not re-focus its editor. In parallel, ADR-0049 drafts
the next TodoMVC gap decision: extending the delegated row kinds with
`dblclick` (click's exact cross-branch agreement) and `checkedChange`
(input's origin rule, `"true"`/`"false"` payload strings) over the existing
`listenDelegatedCells` plumbing — expected to need no further host change.

### What was pleasant

The ABI bump convention made the expensive half mechanical: one
`runtimeAbi := 16`, twenty-one manifest/test reference bumps, and the ADR —
nothing else moved. The emitter's obligation was one guarded statement per
branch side because the replacement arm already knew `want` and the fresh
subtree root (`childAt(cell, 0)`); the focus path navigates from there with
the same `childAt` composition the update targets use. Lean's
default-valued constructor fields meant the new `autoFocus` flag slotted
into `RowNode.element` without touching any construction site, and the
bare-identifier attribute syntax parsed beside `name=value` and
`name={term}` on the first try with no grammar ambiguity.

### Friction

Lean patterns fill omitted default-valued constructor arguments with their
defaults, not wildcards: every pre-existing seven-argument
`.element … reflects` pattern silently became an `autoFocus == false`
match. The build stayed green and the mismatch surfaced only as a runtime
gate failure ("branch edit subtree is not an element") in the elaboration
test, so the fix was an audit of every RowNode element pattern in the
repository — worth remembering for the next model field. Focus stealing
also resists direct browser assertion: a Playwright click focuses the
clicked button, so the no-steal gates pin focus on the clicked control (Add
on row mount, OK on commit) and pin the editor unfocused after a
reorder, rather than asserting an untouched activeElement.

### Bugs found

No framework defect surfaced: the generated module, the three new
compile-fail fixtures, and all browser gates (including the two focus
gates) passed on their first run after the pattern-default audit above.

### Performance observations

Byte-diff proof under the performance freeze: the js-framework-benchmark
`main.mjs` is byte-identical to the pre-round baseline and its manifest
differs only by `"runtimeAbi":16`, so BENCHMARK.md numbers carry forward
unchanged. Components without a reachable marker emit byte-identical
modules — the `focus` import and `row-focus` manifest feature appear only
when a region both declares update actions and carries a marked branch
input — and Branch Lab's single `focus` call site is counted by the
artifact gate.

### Follow-up issue or commit

`feat(component): transfer focus into fresh branch inputs (ABI 16)`,
`test(component): forge the focus gates and teach the guide`, and
`docs(adr): accept the row focus vocabulary and draft the delegation kinds
(ADR-0048, ADR-0049)`. Remaining gaps carried forward: `dblclick`
edit entry and checkbox toggles for TodoMVC parity (ADR-0049 decision
draft — no host change expected), `s!` interpolation absent from row scope
(`++` only), attribute selection limited to one per attribute per element
with a single-field `String` equality predicate, branch cells single-level
and two-branch only with exact click agreement, and child instrumentation
still unreachable through the parent disposer.

## Delegated dblclick and checkbox toggles — Toggle Lab TodoMVC rows

### Scenario exercised

The ADR-0049 round: the closed delegated row kinds grew from three to five
with no host change and no ABI bump. `onDblClick={edit}` binds the
payload-less `dblclick` kind — permitted on the non-button label, so
double-clicking it enters the edit branch (replacement + ADR-0048 focus
transfer) exactly as TodoMVC's observable DOM does — and `onChange={toggle}`
on a `type="checkbox"` input binds the `checkedChange` kind, whose delegated
`checked` boolean lowers to the `"true"`/`"false"` string payload so
`row items toggle (checked : String) := set done checked` stays inside the
sealed `String` update language. The round also closed both ADR-0049 open
questions: the sealed row checked reflection (`checked={done == "true"}`,
`RowReflectTarget.checkedIf` beside the ADR-0047 `value` target) keeps the
toggle state alive across the retained-row update sweep and mounts appended
rows checked, and the validator deliberately does not force a keyboard
sibling next to a dblclick affordance — the guide advises one instead. The
new Toggle Lab proves the pair in the browser: nine gates covering toggle →
class selection on one retained-row update, dblclick edit entry with focus,
the in-editor dblclick no-op, toggle state surviving an edit round-trip,
and per-cell action isolation.

### What was pleasant

The extension really was "two more rows in the kind tables": the host
dispatch had carried `target.checked === true` since ABI 15 and `EventKind`
already named both kinds for the static view, so the emitter's work was one
list literal (`regionEventKinds`), one `conditional` payload expression, and
the reflect-target dispatch — the generated Toggle Lab module's import line
is byte-identical to Branch Lab's. Parametrizing the cross-branch agreement
messages by `kind.name` extended click's rule to dblclick and input's rule
to checkbox change without disturbing a single pinned diagnostic: the
pre-existing compile-fail fixtures passed unchanged. The both-branches-bind
`edit` trick (legal because `draft` mirrors `label` outside editing and
`edit` writes only `mode`) turned the exact-agreement constraint from an
obstacle into the reason an in-editor dblclick cannot clobber the draft —
the equal-value reflection makes the re-dispatch a caret-preserving no-op.

### Friction

`RowReflect` grew a `target` field instead of becoming a two-constructor
inductive: the ABI-16 round's lesson (Lean patterns fill omitted
default-valued constructor arguments with defaults, not wildcards) made the
defaulted-field shape the safe one — every existing `{ value := … }`
literal and `reflect.value` projection kept compiling, and only the
environment audit needed one new `injEq` entry. The checkbox-origin rule
needed a static-attribute lookup (`type="checkbox"`) inside the row
validator — the first row rule that reads an element's attribute list — and
the depth-≥-2 rule shadows payload-class diagnostics in fixtures, so the
dblclick-on-typed-event gate had to nest its span one level deeper before
LRX-VIEW-033 (not -027) surfaced. In row scope `onChange` means
`checkedChange`, not the component-scope `change` (value payload): the
divergence is deliberate (checkbox-only origin rule) but easy to trip over,
so the elaborator carries a comment where the kinds fork.

### Bugs found

No framework defect surfaced: the five-kind validator gates, three new
compile-fail fixtures, the Toggle Lab artifact gate, and all nine browser
gates passed on their first full run. One test-authoring slip (copying
Branch Lab's `editing` class assertions into a Lab whose class selection
follows `done` only) was caught by rereading the generated module before
the first browser run.

### Performance observations

Byte-diff proof under the performance freeze: every file of the
js-framework-benchmark bundle — `main.mjs` and its manifest included — is
byte-identical to the HEAD baseline (compared via a separate git worktree
build), so BENCHMARK.md carries forward unchanged. The unused kinds cost
existing components nothing: listener registration iterates only kinds with
a non-empty action array, so Branch Lab and the benchmark emit the same
modules as before the extension.

### Follow-up issue or commit

`feat(component): delegate row dblclick and checkbox toggles (ADR-0049)`,
`test(component): forge the toggle gates and teach the guide`, and
`docs(adr): accept the delegation kinds (ADR-0049)`. Remaining gaps carried
forward: `s!` interpolation absent from row scope (`++` only), attribute
selection limited to one per attribute per element with a single-field
`String` equality predicate, branch cells single-level and two-branch only
with exact click/dblclick agreement, and child instrumentation still
unreachable through the parent disposer.

## Sealed row aggregates and region broadcasts — Toggle Lab items-left

### Scenario exercised

The ADR-0050 round: the last whole-region TodoMVC gaps — `items-left`,
toggle-all, and clear-completed — closed with no host change and no ABI
bump. `{count items (done == "false")}` and `{count items}` are the two
sealed count forms, mounted as `"0"` text nodes (regions mount empty by
construction) and recomputed by the commit sweep whenever the region was
touched — structurally dirty or holding pending row updates — through the
existing `setText` export, with the count refs and numeric cache riding two
new region-local record slots behind `pending`.
`event completeAll := update items (set done "true")` is the region
broadcast: every row's target takes its sealed row expression evaluated
against that row's old tuple, and the raised dirty flag hands re-rendering
to the keyed reconcile, which retains every surviving key with its handle,
DOM node, and focus. `event clearCompleted := remove items (done == "true")`
is the predicate removal: the kept-array filter plus the same dirty flag
disposes exactly the matching keys. Twelve Toggle Lab browser gates now pin
the counts tracking appends, per-row toggles, broadcasts, removals, and
per-row removes; the broadcast doing exactly one retained-row update per row
(no mounts, moves, or disposals); and the removal disposing exactly the done
rows while the survivor keeps its DOM node.

### What was pleasant

The host reconcile already was the broadcast path: `update(items)` retains
every row whose key survives — keeping its handle and node — while
re-running the retained-row update callback on it, so the emitted broadcast
is a field-write loop plus one flag assignment, and toggle-all's row
identity, class selection, checkbox reflection, and focus preservation all
came for free from machinery ADR-0041/0043/0047/0048/0049 had already
proven. The count sweep needed no new context slots: regions with counts
extend their own record to
`[handle, items, nextKey, dirty, pending, countRefs, countCache]`, so the
slot layout of every existing component is untouched and components without
counts or broadcasts emit byte-identical modules. The dirty-or-pending
touched flag, read before the reconcile and drain consume it, turned "when
must a count recompute" into one boolean per region.

### Friction

Two Lean-side potholes: a pattern variable named `region` inside
`namespace View` resolves to the `View.region` constructor (an
Invalid-pattern error, fixed by renaming — the constructor-shadowing cousin
of the ABI-16 round's pattern-default lesson), and `updateStepTerm?` had to
move below `rowUpdateAssignments` to reuse the sealed assignment lowering,
since forward references need mutual blocks. The JS statement AST has no
mutable `let`, so predicate counts count through a one-cell array
(`count_scan[0] += 1`) — the `scan` cursor precedent from the ADR-0043
dispatch. Making broadcasts mutable-rows citizens meant refactoring
`regionHasUpdates` call sites into an explicit `regionRowsMutate` (update
callback body, `childAt`/`detach` imports, focus reachability) — the
pending-slot sites deliberately stay `regionHasUpdates`, because broadcasts
never enqueue positions. The environment audit wanted six new exact entries
(injEq for the two `Update` constructors, `View.regionCount`, and
`MountedRegionCount`, plus two `_unsafe_rec` collectors).

### Bugs found

No framework defect surfaced: the model gates, the guide-snippet gate, three
new compile-fail fixtures, the updated artifact gate, and all twelve browser
gates (the three ADR-0050 gates included) passed on their first full run
after the constructor-shadowing fix above.

### Performance observations

Byte-diff proof under the performance freeze: every file of the
js-framework-benchmark bundle — `main.mjs` and its manifest included — is
byte-identical to the HEAD baseline (compared via a separate git worktree
build; only the `.leanrx-bundle-owner` marker differs, and it embeds the
output directory name). Counts cost untouched transactions nothing (one
flag read per region with counts) and touched transactions one O(rows) pass
per predicate count; broadcasts and removals are inherently O(rows) and the
reconcile's LIS pass moves nothing when order is preserved.

### Follow-up issue or commit

`feat(component): count, broadcast into, and filter keyed rows (ADR-0050)`,
`test(component): forge the aggregate gates and teach the guide`, and
`docs(adr): accept the row aggregates and region broadcasts (ADR-0050)`.
Remaining gaps carried forward: count and selection predicates are
single-field `String` equality only (no negation and no arithmetic over
counts, so `items-left` counts the canonical `done == "false"` form), `s!`
interpolation absent from row scope (`++` only), broadcast assignments and
removal predicates share those sealed shapes, branch cells single-level and
two-branch only with exact click/dblclick agreement, and child
instrumentation still unreachable through the parent disposer.

## Sealed region filter views — Toggle Lab show-all/active/completed

### Scenario exercised

The ADR-0051 round: the last TodoMVC filter axis — the displayed row set
following the selected filter — closed with no host change and no ABI bump.
`filter items by filter := when "active" (done == "false") then
when "completed" (done == "true")` is the sealed correspondence table: one
`String` component state field mapped to row-field equality predicates,
with the unmatched `"all"` carrying no predicate and showing every row.
The commit sweep applies the table after the region's reconcile and
`updateAt` drain — whenever the region was touched (the ADR-0050
dirty-or-pending flag, now shared between the count and filter sweeps) or
the filter field changed — by writing each row root's `hidden` property
through the existing `setProperty` export, navigating
`childAt(container, i)` from the container element recorded in one new
region-local record slot behind the count slots. Four new Toggle Lab
browser gates pin the filter switch hiding exactly the non-matching rows
with zero region-metrics movement and the same DOM nodes surviving
hide/reveal round trips, a checked row leaving the active set live through
the drain's touched flag, appended rows taking their visibility inside the
appending commit, and broadcasts plus removals composing with an active
filter — with `items-left` counting the full row table throughout.

### What was pleasant

The two rejected alternatives fell out of the existing invariants instead
of needing prototypes: reconciling the visible subset would have broken
the pending slot's position indexing and disposed hidden rows (the exact
identity the retained-key machinery guarantees), so `hidden` recording over
the full reconcile was the only shape that kept every ADR-0041..0050
property untouched. The sweep needed no cache and no new counters — the
ADR-0050 equal-value-broadcast rationale covers per-row `hidden` writes,
and the selection counters (`tx[8]`/`tx[9]`) already had the right meaning.
Reusing the count sweep's touched flag turned "when must visibility
recompute" into one shared const per region, and the container element rode
the region record exactly like the ADR-0050 count refs — dispatch functions
reach DOM references through the context alone, and the slot layout of
every existing component is untouched.

### Friction

The `by` keyword in the new item syntax is already a Lean token, so the
ident-led rule needed no de-reservation — but the arm shape had to be an
application term (`when "active" (done == "false")`) because `=>` cannot
appear in a term-level table; the `set field (expr)` step precedent made
that spelling consistent. The count sweep's touched const moved out of its
`unless counts.isEmpty` block to be shared with the filter sweep, which
required care to keep count-only regions byte-identical (same const name,
same emission order). The environment audit wanted one new exact entry
(`RegionFilter.mk.injEq`), and the match-chain in `ComponentSpec.check`
gained one more validator level, re-indenting the graph-planning arms.

### Bugs found

No framework defect surfaced: the model gates, the elaborator and
guide-snippet gates, three new compile-fail fixtures, the updated artifact
gate, and all sixteen browser gates (the four ADR-0051 gates included)
passed on their first full run.

### Performance observations

Byte-diff proof under the performance freeze: every file of the
js-framework-benchmark bundle — `main.mjs` and its manifest included — is
byte-identical to the HEAD baseline (compared via a separate git worktree
build; only the `.leanrx-bundle-owner` marker differs, and it embeds the
output directory name). Components without filters emit byte-identical
modules, Toggle Lab's import lines are byte-identical to the ADR-0050
round's, and the filter sweep costs untouched transactions one boolean
read; touched or filter-switching transactions pay one O(rows) hidden
pass, and equal-value property writes are WHATWG no-ops.

### Follow-up issue or commit

`feat(component): select keyed row visibility by sealed filter tables
(ADR-0051)`, `test(component): forge the filter gates and teach the
guide`, and `docs(adr): accept the sealed region filter views (ADR-0051)`.
Remaining gaps carried forward: filter arms are single-field `String`
equality only (no negation, no multi-field conjunction, at most one filter
per region, no explicit empty-predicate arm), count and selection
predicates share those sealed shapes, `s!` interpolation absent from row
scope (`++` only), branch cells single-level and two-branch only with
exact click/dblclick agreement, and child instrumentation still
unreachable through the parent disposer.

## Sealed row key branching — Toggle Lab Enter-commit and Escape-revert

### Scenario exercised

The ADR-0052 round: the TodoMVC editor's keyboard contract — commit on
Enter, revert on Escape, ignore everything else — closed with no host
change and no ABI bump. `row items keys (pressed : String) :=
when "Enter" (set label draft, set mode "view") then when "Escape"
(set draft label, set mode "view")` is the sealed key table: the declared
parameter is the discriminant, named in the head and compared implicitly by
each arm — the ADR-0051 filter-table shape carried into row scope — and a
key outside the sealed Enter/Escape set is a no-op (no row scan, no field
write, no `updateAt`, no region trace). The equality branches run inside
the generated region dispatch function over the `eventKey` argument
`listenDelegatedCells` has passed since ABI 15; the keydown listener and
its per-cell action array were already paid for by ADR-0046. Three new
Toggle Lab browser gates pin Enter committing the draft as exactly one
retained-row update with identity preserved, Escape restoring the pre-edit
draft (with the next edit entry pre-filled through the value reflection and
a commit-after-revert round-tripping the restored text), and non-matching
keys (`ArrowLeft`, `Shift`) moving no region metrics while keeping the
editor's branch, value, and focus.

### What was pleasant

The evaluation the goal asked for — dispatcher-internal key equality versus
a new delegated kind — resolved decisively on existing invariants: minting
`keydownEnter`/`keydownEscape` kinds would have multiplied the listener
registrations, per-kind action arrays, and ADR-0047 cross-branch agreement
rules by the key set (and ADR-0049 had already rejected the open kind
table), while the dispatch function held the unread `eventKey` argument all
along. The emitter refactor fell out cleanly: the ADR-0043
scan-evaluate-assign-queue sequence extracted into one shared
`rowUpdateApplyStmts` helper that the plain update action and each key arm
now both call, and every existing lab's artifact gate proved the
refactoring byte-identical. The `when` arm reused the ADR-0051 application
term shape unchanged, so the grammar needed no new syntax rule — arms are
plain terms behind the existing `then` separator.

### Friction

The arm parser had to live inside the *typed* row item only: a `when` arm
in a payload-less `row` item pattern-matches the generic
`set field (expr)` step shape closely enough that the default error
message pointed at the wrong repair, so `LRX-ELAB-121` special-cases it
("declares a String payload parameter"). The environment audit wanted one
new exact entry (`RowAction.keySelect.injEq`), and the `verifyToggle`
elaborator gate pins the whole row event vocabulary as one list literal,
so the new event re-pinned the editor's binding list too. Choosing where
the sealed key set lives took a moment — it sits beside `RowAction` as
`RowAction.keyLiterals`, so validation and the ADR name one authority.

### Bugs found

No framework defect surfaced: the model gates (ten new LRX-VIEW-039
rejections plus the good forged table), the elaborator and guide-snippet
gates, three new compile-fail fixtures, the updated artifact gate, and all
nineteen browser gates (the three ADR-0052 gates included) passed on their
first full run.

### Performance observations

Byte-diff proof under the performance freeze: every file of the
js-framework-benchmark bundle — `main.mjs` and its manifest included — is
byte-identical to the HEAD baseline (compared via a stash-swap build; only
the `.leanrx-bundle-owner` marker differs, and it embeds the output
directory name). Components without a key-branched event emit
byte-identical modules — the shared-helper refactoring of the dispatch
emitter is proven by every other lab's unchanged artifact gate — and
Toggle Lab's import line is byte-identical to Branch Lab's. A matched key
costs the same scan-and-drain as the OK button's update; a non-matching
key costs one empty transaction, the per-keystroke price ADR-0046 already
accepted for `retype`.

### Follow-up issue or commit

`feat(component): branch keydown row events on sealed key literals
(ADR-0052)`, `test(component): forge the key-branch gates and teach the
guide`, and `docs(adr): accept the sealed row key branching (ADR-0052)`.
Remaining gaps carried forward: the key set is sealed at Enter/Escape,
arms select assignment stages only (no key-branched `remove` — TodoMVC's
destroy-on-empty-commit still needs row-field guards that do not exist),
filter arms and count predicates stay single-field `String` equality, `s!`
interpolation absent from row scope (`++` only), branch cells single-level
and two-branch only with exact click/dblclick agreement, and child
instrumentation still unreachable through the parent disposer.

## Sealed row field guards — Toggle Lab destroy-on-empty-commit

### Scenario exercised

The ADR-0053 round: TodoMVC's destroy-on-empty-commit — the gap ADR-0052's
first open question recorded — closed with no host change and no ABI bump.
`row items commit := if draft == "" then remove else (set label draft,
set mode "view")` and the same `if` shape inside the Enter key arm are the
sealed remove-if guard: one row-field equality against one string literal,
carried on the `RowStage` shape the plain update action and every ADR-0052
key arm now share. A guard hit removes the dispatching row through the
exact kept-filter, dirty flag, and reconcile the ✕ button's sealed `remove`
runs — no field write, no `updateAt` queue entry — and a miss commits the
else-steps byte-for-byte as the unguarded stage did. Escape stays
unguarded by choice: reverting an empty draft restores the label instead
of destroying the row. Three new Toggle Lab browser gates pin Enter on an
empty draft as exactly one row disposal (plus the survivor's re-render
from the dirty reconcile — the price every removal already paid), with
survivor DOM identity preserved and the counts following; the OK button
agreeing through the guarded commit with a nonempty draft still taking
the ordinary commit path; and Escape on an empty draft keeping the row.

### What was pleasant

The evaluation the goal asked for — dispatcher-internal guard equality
versus a general row conditional vocabulary — resolved on the same
invariants as the last two rounds: the ADR-0043 scan already resolves the
dispatching row's field tuple before any write, so the guard is one
comparison on data the dispatch function already holds, while an open
`if`/`else` over row expressions would have opened the sealed update
language into control flow that ADR-0049 and ADR-0052 had each already
declined. Attaching the guard to the stage rather than minting a
`guardedRemove` action constructor meant `update` and `keySelect` arms
gained the vocabulary through one shape, and the emitted guard branch
reuses the removal statements extracted from the `remove` action into one
shared helper — proven byte-identical by every other lab's unchanged
artifact gate and a byte-identical js-framework-benchmark bundle.

### Friction

Changing `RowAction.update`'s payload from a bare assignment list to
`RowStage` touched every forged-spec literal in the model, elaborator, and
guide gates (~25 mechanical `⟨…, none⟩` wrappings — scripted, but churn).
The guarded surface had to be rejected in *typed* row events with its own
repair (`LRX-ELAB-122`), mirroring the ADR-0052 lesson that a
close-but-wrong step shape otherwise reports the generic `set` message
pointing at the wrong fix. And the first browser gate draft pinned the
removal as "one disposal, zero updates" — wrong: every removal re-renders
retained survivors through the dirty reconcile, so the honest pin is
disposals +1 *and* updates +1 for the one survivor, the metrics contract
the ✕ button always had.

### Bugs found

No framework defect surfaced: the model gates (the good guarded update and
guarded key arm plus three LRX-VIEW-040 rejections), four LRX-ELAB-122
compile-fail fixtures, the updated artifact and elaborator gates, and all
twenty-two Toggle Lab browser gates (the three ADR-0053 gates included)
passed with one first-run failure — the miscalibrated metrics pin above,
a test bug, not a framework bug.

### Performance observations

Byte-diff proof under the performance freeze: every file of every other
lab and of the js-framework-benchmark bundle — `main.mjs` and manifest
included — is byte-identical to the HEAD baseline (full before/after
builds into the scratchpad; only Toggle Lab's module and manifest change,
gaining the guard branches and the `row-guards` feature). A guarded
commit's miss path emits the identical statement sequence as before behind
one extra comparison; a guard hit swaps the write-and-drain for the
removal reconcile that already existed.

### Follow-up issue or commit

`feat(component): guard row stages on sealed field equality (ADR-0053)`,
`test(component): forge the row-guard gates and teach the guide`, and
`docs(adr): accept the sealed row field guards (ADR-0053)`. Remaining gaps
carried forward: no trim normalization (a whitespace-only draft commits as
a whitespace label — a future row-expression `trim`, not a guard shape),
guards sealed at single-field `String` equality selecting remove-or-commit
only, the key set sealed at Enter/Escape, filter arms and count predicates
single-field equality, `s!` interpolation absent from row scope, branch
cells single-level and two-branch with exact click/dblclick agreement, and
child instrumentation still unreachable through the parent disposer.

## Sealed row expression trim — Toggle Lab whitespace commit contract

### Scenario exercised

The ADR-0054 round: TodoMVC's trim contract — the gap ADR-0053's first
open question recorded — closed with no host change and no ABI bump.
`trim` joins the sealed row expression vocabulary as its one unary
(`trim field` / `trim (expr)`, ASCII whitespace stripped from both ends,
aligned with Lean's `String.trim`), and the remove-if guard's subject
generalized from a field index to a sealed row expression pinned to
`field` or `trim field` — an expression vocabulary extension, explicitly
not a guard extension. Toggle Lab guards both commit paths on
`trim draft == ""` and commits `set label (trim draft), set draft (trim
draft), set mode "view"`: a whitespace-only draft's Enter (or OK) destroys
the row exactly as an empty one does, `"  x  "` stores as `"x"`, and the
re-mirrored draft keeps the next edit entry starting from the stored
label. Escape's revert arm stays unguarded and untrimmed. Two new browser
gates pin the whitespace removal (one disposal, one survivor update,
survivor identity preserved, counts following) and the trimmed store with
the re-entered editor reflecting the trimmed draft.

### What was pleasant

The guard-subject generalization paid for itself immediately: replacing
the guard's `field : Nat` with `value : RowExpr` let the emitted guard
comparison ride the exact `rowExprJs` lowering the commit assignments
use, so raw-field guards emit byte-identical comparisons (proven by the
byte-diff) and the trimmed guard needed zero new emission logic beyond
the one `RowExpr.trim` case — which itself reuses the `asciiTrimPattern`
literal the hand-written Todo backend has emitted since M5. The
ADR-0053 sealing checks localized cleanly: `RowExpr.guardSubject?` is the
whole shape rule, shared by the plain-stage and key-arm validations.

### Friction

The trim contract is not one assignment: the first draft committed only
`set label (trim draft)` and left the raw draft in the row, so the next
edit entry reflected `"  x  "` — the lab's draft-mirrors-label invariant
(and TodoMVC's editor-starts-from-title behavior) silently broken. The
honest commit stage re-mirrors the draft (`set draft (trim draft)`) in
the same simultaneous update; the elaborator, artifact, and browser pins
all had to carry the third assignment. And the guard-subject surface
needed its own `LRX-ELAB-122` repair for near-miss expressions
(`trim (draft ++ "!")`), since the generic guard message would point at
the wrong fix — the ADR-0052/0053 lesson, third time.

### Bugs found

No framework defect surfaced: the model gates (the good trimmed guard and
trimmed key arm plus five non-subject/out-of-bounds LRX-VIEW-040
rejections), two new compile-fail fixtures (LRX-ELAB-122 non-subject
guard, LRX-ELAB-115 trim over an unknown field), the updated artifact and
elaborator gates, and all twenty-four Toggle Lab browser gates (the two
ADR-0054 gates included) passed; the draft-mirror miss above was caught
while drafting the browser gate, before any commit.

### Performance observations

Byte-diff proof under the performance freeze: every file of every other
lab and of the js-framework-benchmark bundle — `main.mjs` and manifest
included — is byte-identical to the HEAD baseline (full before/after
builds into the scratchpad; only Toggle Lab's module, manifest, and graph
spans change, gaining the trim calls and the `row-trim` feature). A
trimmed guard costs one `replace` on the dispatching row's field at
dispatch time; the guard-hit removal and the miss path's write-and-drain
shapes are unchanged.

### Follow-up issue or commit

`feat(component): trim row expressions through one sealed unary
(ADR-0054)`, `test(component): forge the row-trim gates and teach the
guide`, and `docs(adr): accept the sealed row expression trim (ADR-0054)`.
Remaining gaps carried forward: component scope (`RxExpr`) has no trim —
TodoMVC's top-level new-todo input cannot normalize its draft yet; the
ADR-0050 predicate removal, ADR-0051 filter arms, ADR-0044 class
selection, and ADR-0049 checked reflection still compare raw fields;
guards sealed at single-field equality selecting remove-or-commit only;
the key set sealed at Enter/Escape; `s!` interpolation absent from row
scope; branch cells single-level and two-branch with exact click/dblclick
agreement; and child instrumentation still unreachable through the parent
disposer.

## Component-scope add path — Toggle Lab new-todo contract

### Scenario exercised

The ADR-0055 round: TodoMVC's new-todo add contract — the gap ADR-0054's
first open question recorded — closed with no host change and no ABI
bump. `RxExpr` gains its `String` trim unary (`trim field` /
`trim (expr)` in `rx%`, ASCII both-ends, riding the same
`asciiTrimPattern` emission as the ADR-0054 row trim through the ordinary
scalar evaluators), and component events gain the sealed skip-if guard:
`event addTodo := if trim draft == "" then skip else (append items (trim
draft, trim draft, "false", "view"), set draft "")`. Toggle Lab mirrors
the draft into a controlled new-todo input (ADR-0038, per-keystroke
`setDraft`), and the guard hit is a whole-event no-op — the dispatch
function returns before the transaction begins, so a whitespace-only Add
leaves the transaction counters, the trace list, the region metrics, the
counts, and the draft itself exactly untouched — while a valid draft
appends one row with the trimmed label and resets the draft in the same
transaction. Enter-to-add is recorded as a gap: component scope has no
key branching, so the contract is proven through the Add button path.

### What was pleasant

Both halves reused existing machinery to the letter. The `rx%` trim is
one constructor threaded through `UnaryPrim` → `ReactiveIR` →
`Lower.rxExpr` → the scalar backend's `UnaryPlan`, and the emitted append
evaluator came out as exactly the hand-written Todo backend's replace;
the differential harness pinned Lean-vs-JS agreement (NBSP preserved on
both sides) with three table rows. The guard slotted into
`transactionShell` as one optional statement before the begin
bookkeeping, so "no write, no append, no trace" is true by construction
rather than by discipline — and unguarded components are byte-identical
because the statement simply is not emitted.

### Friction

Two environment potholes, no design potholes. `EventSpec` gained an
optional `guard?` field and the elaborator's positional
`EventSpec.mk name update span` stopped elaborating — the optParam is not
auto-filled for that partially-applied shape against the schema abbrev —
so the generated term now passes `none` explicitly. And Lean's
`String.trim` is deprecated in v4.33 (`String.trimAscii` returns a
`Slice`), while the whole core UTF-8 machinery is classical: adding the
one `stringTrim` case to `RxExpr.eval` pushed `Classical.choice` into the
transitive axiom manifests of `eval_congr_on_deps` and the eval equation
lemmas. The environment audit's exact-manifest design earned its keep —
the change surfaced as three reviewed lines with a comment, not a silent
drift. The surface ordering rule (plain events before typed events in the
declaration inventory) bit the guide snippet once (`LRX-ELAB-103`).

### Bugs found

No framework defect surfaced: the model gates (the good guarded event
with its summary guard-read and the LRX-TYPE-114 derived-subject
rejection), two new compile-fail fixtures (LRX-ELAB-123 non-empty guard
literal, LRX-ELAB-123 non-skip guard hit), the trim staging/eval/
differential gates, the updated elaborator, artifact, and guide gates,
and all twenty-six Toggle Lab browser gates (the two ADR-0055 gates
included) passed.

### Performance observations

Byte-diff proof under the performance freeze: every file of every other
lab and of the js-framework-benchmark bundle — `main.mjs` and manifest
included — is byte-identical to the HEAD baseline (full before/after
builds into the scratchpad; only Toggle Lab's module, manifest, and graph
change, gaining the guarded event, the controlled input, and the
`typed-events`/`event-guards`/`controlled-props` features). The guard
costs one comparison plus one `replace` at dispatch time, before any
bookkeeping; a guard hit costs nothing else at all.

### Follow-up issue or commit

`feat(component): close the component-scope add path (ADR-0055)`,
`test(component): forge the add-path gates and teach the guide`, and
`docs(adr): accept the component-scope add path (ADR-0055)`.
Remaining gaps carried forward: Enter-to-add needs a component-scope key
selection (the ADR-0052 shape lifted out of row scope) or another form;
the guard literal is sealed at the empty string; the ADR-0045 selections,
ADR-0050 predicate removal, ADR-0051 filter arms, ADR-0044 class
selection, and ADR-0049 checked reflection still compare raw fields; row
guards stay single-field remove-or-commit; the key set stays sealed at
Enter/Escape; `s!` interpolation absent from row scope; branch cells
single-level and two-branch with exact click/dblclick agreement; and
child instrumentation still unreachable through the parent disposer.

## Component-scope key branching — Toggle Lab Enter-to-add

### Scenario exercised

The ADR-0056 round: TodoMVC's Enter confirmation on the new-todo input —
the gap ADR-0055's first open question recorded — closed with no host
change and no ABI bump. The ADR-0052 sealed key selection lifts to
component scope as the key-branched component event: `event confirmAdd
(pressed : String) := when "Enter" (if trim draft == "" then skip else
(append items (trim draft, trim draft, "false", "view"), set draft ""))`,
bound `onKeyDown={confirmAdd}` beside the per-keystroke `setDraft` on the
same controlled input. The declared parameter is the discriminant — named
in the head, compared implicitly by each arm, unspellable inside an arm
body — key literals come from the sealed Enter/Escape set, and each arm
body is the ADR-0055 event-body language (ordinary steps, optionally
behind the skip guard), so Enter *is* the Add button's guarded add by
construction: whitespace-only Enter is a whole-event no-op, valid Enter
appends the trimmed label and resets the draft, and a key outside the
table returns from the dispatch function before the context is even
destructured.

### What was pleasant

The lift was almost entirely reuse. The arm bodies elaborate through the
same `updateStepTerm?`/`guardedStepsTerm` path the ADR-0055 guard miss
uses (one refactor split `guardedEventTerm` into pieces both callers
share); validation runs the arms through the exact per-event obligation
loops by generalizing them over `(name, update, guard?, span)` tuples; and
the backend emits each arm as one ordinary `transactionShell` function —
so the guard hit's no-op, the trace discipline, and the commit sweep are
inherited, not re-implemented. The host side cost nothing: `listenKey`
has forwarded `event.key` to generated dispatch functions since the form
events host split, so the dispatch function's `pressed === "Enter"` is
the entire new runtime surface.

### Friction

Two environment potholes again. The typed-event syntax rule had to grow
from one term to a `then`-separated sequence for the `when` arms, which
silently broke the quotation-pattern matches in the elaborator's two
passes — they were rewritten as raw syntax-kind dispatches (the row items
already work that way). And the elaborator edit renumbered the generated
unsafe evaluator wrapper (`unsafe_5` → `unsafe_7`), which the environment
audit caught as an exact-name mismatch beside the two new `KeyEventSpec`
injectivity lemmas — three reviewed lines, no silent drift. Structure
instance literals in the forged model gates also reminded us that Lean's
field-list indentation is column-sensitive inside `#[{ … }]`.

### Bugs found

No framework defect surfaced: the model gates (the forged good key event
with its arm table and summary guard-read union, three LRX-TYPE-115
sealed-set/duplicate/empty rejections, two LRX-VIEW-041 binding
rejections), two new compile-fail fixtures (LRX-ELAB-124 payload
reference in an arm, LRX-ELAB-124 mixed arm/step table), the updated
elaborator, artifact, and guide gates, and all twenty-nine Toggle Lab
browser gates (the three ADR-0056 gates included) passed.

### Performance observations

Byte-diff proof under the performance freeze: every file of every other
lab and of the js-framework-benchmark bundle — `main.mjs` and manifest
included — is byte-identical to the HEAD baseline (full before/after
builds into the scratchpad; only Toggle Lab's module, manifest, and graph
change, gaining the key event, the `listenKey` registration, and the
`event-key-branches` feature). A non-matching key costs one string
comparison per arm and returns — strictly cheaper than row scope's
non-match, which begins and commits an empty transaction through the
shared region dispatch.

### Follow-up issue or commit

`feat(component): close the component-scope Enter path (ADR-0056)`,
`test(component): forge the Enter gates and teach the guide`, and
`docs(adr): accept component-scope key branching (ADR-0056)`.
Remaining gaps carried forward: the component-scope Escape arm is sealed
but unproven (no new-todo revert contract exists to prove it); the
trimmed `disabled` affordance for the Add button stays open; the guard
literal is sealed at the empty string; the ADR-0045 selections, ADR-0050
predicate removal, ADR-0051 filter arms, ADR-0044 class selection, and
ADR-0049 checked reflection still compare raw fields; row guards stay
single-field remove-or-commit; the key set stays sealed at Enter/Escape;
`s!` interpolation absent from row scope; branch cells single-level and
two-branch with exact click/dblclick agreement; and child instrumentation
still unreachable through the parent disposer.

## Trimmed attribute selection — the Add affordance

### Scenario exercised

The ADR-0057 round: TodoMVC's grayed Add button — the affordance ADR-0055's
third open question recorded and ADR-0056 restated — closed with no host
change and no ABI bump. The ADR-0045 sealed selection subject may now sit
behind the one ADR-0054/0055 trim unary: Toggle Lab's Add button carries
`disabled={trim draft == ""}`, so the disabled property reflects exactly
the ASCII-trimmed equality the ADR-0055 skip guard evaluates — the button
mounts disabled on the empty draft, stays disabled across whitespace-only
typing, enables on the first non-whitespace character, and re-disables when
the guarded add resets the draft through the commit sweep. The dispatch
guard stays the contract on both add paths (ADR-0055 rejection 2
re-affirmed): the whitespace-Add browser gate was reconstructed against the
guard itself — a synthetic click handed to the disabled button still
returns before any transaction — so it cannot go vacuous behind the grayed
button.

### What was pleasant

The subject extension was one flag riding three existing rails. `AttrSelect`
gained a defaulted `trimmed` field (all existing constructions compile
unchanged); the elaborator matches the `trim` head by name exactly the way
the guard and row-expression elaborators already do (ADR-0035 style, so
`trim` stays an ordinary identifier); and the backend wraps the subject in
the same `asciiTrimPattern` emission the skip guard prints — a shared
`asciiTrimJs` helper now serves both — inside the untouched
evaluate-compare-write sweep block. Byte-diff proof came out clean on the
first build: only Toggle Lab's module, manifest, and graph changed, and the
mount emission put the initial disabled write exactly where the ADR-0045
layout said it would (attr slots behind the prop slots, regions two slots
later).

### Friction

The known pattern-arity gotcha, again: adding a defaulted constructor field
turns full-positional accessor patterns non-exhaustive (Lean fills omitted
defaulted arguments with their defaults in pattern position, not
wildcards), so the `AttrSelect` accessors were rewritten with `..` where a
leading binder suffices and full arity where the span sits mid-signature.
Playwright's actionability check made the old whitespace-Add gate
physically unclickable — which is the affordance working, but it forced the
gate to dispatch the synthetic click through `evaluate` to keep observing
the guard rather than the button.

### Bugs found

No framework defect surfaced: the model gates (three forged trimmed
selections accepted with their trim flags, `select:…:trim:2` debug markers,
and graph sinks; the LRX-VIEW-032 rejection unchanged on a trimmed
subject), two new compile-fail fixtures (a non-`trim` applied head and a
negated predicate, both LRX-VIEW-012), the updated elaborator, artifact,
and guide gates, and all thirty-one Toggle Lab browser gates (the two
ADR-0057 gates and the reconstructed ADR-0055 gate included) passed.

### Performance observations

Byte-diff proof under the performance freeze: every file of every other lab
and of the js-framework-benchmark bundle — `main.mjs` and manifest included
— is byte-identical to the HEAD baseline (full before/after builds into the
scratchpad; only Toggle Lab's module, manifest, and graph change, gaining
the `attr-selections` feature, the attr context slots, and the sweep
block). A trimmed selection costs one `replace` per evaluation and only
when its field changed; the boolean cache keeps equal-value sweeps
write-free — the browser gate pins one `attr:0:disabled:evaluated` and zero
writes for a trailing-space keystroke.

### Follow-up issue or commit

`feat(component): close the Add affordance with the trimmed selection
subject (ADR-0057)`, `test(component): forge the affordance gates and teach
the guide`, and `docs(adr): accept the trimmed attribute selection
(ADR-0057)`. Remaining gaps carried forward: the component-scope Escape arm
is sealed but unproven (no new-todo revert contract exists to prove it);
the ADR-0050 predicate removal, ADR-0051 filter arms, ADR-0044 row class
selection, and ADR-0049 checked reflection still compare raw fields; the
guard literal is sealed at the empty string; row guards stay single-field
remove-or-commit; the key set stays sealed at Enter/Escape; `s!`
interpolation absent from row scope; branch cells single-level and
two-branch with exact click/dblclick agreement; and child instrumentation
still unreachable through the parent disposer.

## Empty-region visibility — hide-when-empty

### Scenario exercised

The ADR-0058 round: TodoMVC's hide-when-empty parity — the main/footer
sections that appear with the first todo and disappear with the last —
closed with no host change and no ABI bump. The attribute-selection
vocabulary gained the one sealed region-subject form:
`hidden={count items == 0}` on Toggle Lab's items list wrapper (the
region's own `<ul>` container) reflects emptiness of the region's row
table into the wrapper's `hidden` boolean property. The wrapper mounts
hidden — regions mount empty by construction, the ADR-0050 `"0"`
reasoning, so the mount-time cache value is the literal `true` — the
first append reveals it, and the ✕ removal, the ADR-0053 guarded empty
commit, and `completeAll` + `clearCompleted` each re-hide it through the
same region-touch sweep the count texts ride. The ADR-0051 filter gate
pins the sharp edge: with every row filter-hidden the wrapper stays
revealed, because the subject is the row table's total, never the
displayed rows — and a filter change alone does not even re-evaluate the
selection, since it never touches the region.

### What was pleasant

The ADR-0050 count-text architecture paid for itself: the hidden
selection is exactly "a count text that writes a boolean property", so
the whole sweep — the shared `region_touched` flag, the
evaluate-compare-write shape, the cache slot — already existed, and the
new code is one loop beside the counts. Riding the ADR-0045 attr slots
(refs and cache in the existing context positions) meant no region-record
layout change and no context change: Toggle Lab's context stays eleven
slots and the region record stays eight. The component command's count
rewrite generalized cleanly from children to attributes; the sealed
rejections (predicate subject, threshold literal, general expressions)
fall out of one match with three arms.

### Friction

`AttrSelect.fieldIndex` and `equals` were total accessors that every
selection could answer; the region-subject selection can't, and Lean's
totality made the dishonest options (a junk `0` field) visible enough to
refuse. They became `fieldIndex?`/`equals?`, which rippled through three
test tuples — mechanical, but a reminder that accessor totality is API
design. The other stumble was Playwright's visibility model: a `<ul>`
whose rows are all filter-hidden has an empty bounding box, so
`toBeVisible()` reports the *revealed* wrapper as hidden; the gate
observes the `hidden` property and the computed display directly instead.
And `throwErrorAt` interpolates its string literal, so the diagnostic
text `hidden={count region == 0}` needed its brace escaped — the compiler
error ("unknown identifier `count`") pointed at a string that looked
perfectly inert.

### Bugs found

No framework defect surfaced: the forged model gates (accepted wrapper
selection with its debug marker, boolean value type, and graph exclusion;
the LRX-VIEW-042 unknown region; the LRX-VIEW-001 duplicate), two new
compile-fail fixtures (a predicate count subject and a nonzero threshold
literal, both LRX-ELAB-125), the updated elaborator, artifact, and guide
gates, and all thirty-four Toggle Lab browser gates (the three ADR-0058
gates included) passed.

### Performance observations

Byte-diff proof under the performance freeze: every file of every other
lab and of the js-framework-benchmark bundle — `main.mjs` and manifest
included — is byte-identical to the HEAD baseline (full before/after
builds into the scratchpad); only Toggle Lab's module, manifest (gaining
`region-visibility`), and graph (source spans only — the selection joins
no graph node) change. A hidden selection costs one `length` read and one
equality per region-touching transaction, and only there — a filter
change skips it entirely — and the boolean cache keeps every non-flip
write-free: the browser gate pins one `attr:1:hidden:evaluated` and zero
writes for appending a second row.

### Follow-up issue or commit

`feat(component): close the hide-when-empty parity with the region-subject
hidden selection (ADR-0058)`, `test(component): forge the visibility gates
and teach the guide`, and `docs(adr): accept the empty-region visibility
(ADR-0058)`. Remaining gaps carried forward: the component-scope Escape
arm is sealed but unproven (no new-todo revert contract exists to prove
it); predicate-driven visibility (hiding the clear-completed affordance
while no row is done) is recorded as ADR-0058's first open question; the
ADR-0050 predicate removal, ADR-0051 filter arms, ADR-0044 row class
selection, and ADR-0049 checked reflection still compare raw fields; the
guard literal is sealed at the empty string; row guards stay single-field
remove-or-commit; the key set stays sealed at Enter/Escape; `s!`
interpolation absent from row scope; branch cells single-level and
two-branch with exact click/dblclick agreement; and child instrumentation
still unreachable through the parent disposer.

## Predicate-count visibility — the clear-completed affordance

### Scenario exercised

The ADR-0059 round: TodoMVC's clear-completed visibility parity — the
button that exists only while some row is completed — closed with no host
change and no ABI bump, resolving ADR-0058's first open question. The
sealed hidden selection gained the one predicate-count subject:
`hidden={count items (done == "true") == 0}` on Toggle Lab's Clear
completed button reflects "no row satisfies the ADR-0050 predicate" into
the button's `hidden` boolean property, riding the exact ADR-0058
machinery — the same region-touch re-evaluation, the same shared attr
slots, the same `setProperty` export, the same boolean cache. The button
mounts hidden (an empty region satisfies no predicate — the same literal
`true` the total subject mounts with), a not-done append is an
evaluate-only sweep (the scan counts zero, the compare swallows the
write), the first done toggle reveals it, untoggling the last done row,
`clearCompleted` itself, or the ✕ removal of the last done row re-hides
it, a filter change alone re-evaluates nothing while the button stays
revealed over its filter-hidden done row, and the `completeAll` broadcast
leaves it revealed through the equal-value compare. The rejections
sharpened alongside: the zero literal is sealed for both subjects, and
the predicate field resolves against the declared row fields at the
surface (`LRX-ELAB-119`) and bounds-checks at the model (`LRX-VIEW-042`).

### What was pleasant

The subject was already in the vocabulary twice over: `hiddenIfEmpty`
took the exact optional `(Nat × String)` predicate `RegionCount` has
carried since ADR-0050, the surface rewrite took the exact
`regionCount% "region" fieldIndex "literal"` optional-argument shape, and
the backend sweep took the count sweep's scan loop with `=== 0` appended.
Every layer had a precedent to copy, so the diff is mostly the ADR-0058
code paths growing an `Option` — and the mount-time reasoning ("an empty
region satisfies no predicate") needed no new code at all, because the
constant-`true` lowering was already subject-agnostic. The attr-slot
sharing meant the new selection slotted between the existing two with
nothing but index shifts in the gates.

### Friction

The attr index shifts were the bulk of the test churn: the wrapper's
selection moved from `attr:1` to `attr:2` because the button precedes the
`<ul>` in document order, so every ADR-0058 trace label in the browser
and artifact gates needed relabeling — mechanical, but a reminder that
trace labels indexed by document order are load-bearing test surface. The
sharper edge was self-inflicted by the parity itself: an existing
ADR-0050 gate clicked Clear completed while nothing matched (pinning the
no-op removal), and with the affordance in place that button is now
hidden — Playwright rightly refuses to click it. The gate now dispatches
the click structurally with `includeHidden: true`, which is also the
honest statement of the ADR-0057 stance: the affordance is not the
contract, and the removal stays a no-op wherever it is triggered from.
And one fixture flipped meaning: HiddenPredicateCount pinned "predicate
counts are rejected" and would now compile, so it became
HiddenPredicateThreshold (the zero-literal seal on the predicate form)
plus HiddenPredicateUnknownField (the surface field resolution).

### Bugs found

No framework defect surfaced: the forged model gates (accepted predicate
selection with its `select:hidden:r:0:true` debug marker, boolean value
type, and graph exclusion; the out-of-bounds predicate field
LRX-VIEW-042), the two replacement compile-fail fixtures, the updated
elaborator, artifact, and guide gates, and all thirty-seven Toggle Lab
browser gates (the three new ADR-0059 gates included) passed.

### Performance observations

Byte-diff proof under the performance freeze: every file of every other
lab and of the js-framework-benchmark bundle — `main.mjs` and manifest
included — is byte-identical to the HEAD baseline (full before/after
builds into the scratchpad); only Toggle Lab's module, manifest (gaining
`predicate-visibility`), and graph (source spans only — the selection
joins no graph node) change. A predicate hidden selection costs one
row-table scan per region-touching transaction — the ADR-0050 count-text
cost, and only there: a filter change skips it entirely — and the boolean
cache keeps every non-flip write-free: the browser gates pin the not-done
append and the completeAll broadcast as one evaluation and zero writes
each.

### Follow-up issue or commit

`feat(component): hide the clear-completed affordance on the predicate
count (ADR-0059)`, `test(component): forge the predicate-visibility gates
and teach the guide`, and `docs(adr): accept the predicate-count
visibility (ADR-0059)`. Remaining gaps carried forward: the
component-scope Escape arm is sealed but unproven (no new-todo revert
contract exists to prove it); affordance-contract agreement (the hidden
button and the no-op removal read the same predicate but nothing ties
them) is recorded as ADR-0059's first open question; the ADR-0050
predicate removal, ADR-0051 filter arms, ADR-0044 row class selection,
and ADR-0049 checked reflection still compare raw fields; the guard
literal is sealed at the empty string; row guards stay single-field
remove-or-commit; the key set stays sealed at Enter/Escape; `s!`
interpolation absent from row scope; branch cells single-level and
two-branch with exact click/dblclick agreement; and child instrumentation
still unreachable through the parent disposer.

## Region-checked reflection — the toggle-all display half

### Scenario exercised

The ADR-0060 round: TodoMVC's toggle-all display parity — the checkbox
that is checked exactly while every row is complete — closed with no host
change and no ABI bump. The sealed region-count boolean gained its second
export: `checked={count items (done == "false") == 0}` on Toggle Lab's
toggle-all checkbox reflects "no row is still active" into the box's
`checked` property, riding the exact ADR-0058/0059 machinery — the same
region-touch re-evaluation, the same shared attr slots, the same
`setProperty` export, the same boolean cache, with `attr:{index}:checked`
labels. The box mounts checked (an empty region has no row failing the
predicate — vacuously all complete), the first not-done append unchecks
it, the `completeAll` broadcast re-checks it, untoggling the last done
row or appending unchecks it again, the ✕ removal of the last not-done
row re-checks it through the ordinary reconcile, `clearCompleted`
draining the region restores the vacuous truth as an evaluate-only sweep
(one evaluation, no write), and a filter change alone re-evaluates
nothing while every not-done row is filter-hidden. Two static-scope rules
shipped under the new `LRX-VIEW-043`: the selection demands a static
`type="checkbox"` input (the ADR-0049 origin rule in static scope), and
the box's `onChange={completeAll}` is the payload-less toggle binding — a
static change binding naming a plain component event, mounted through the
plain `listen` export with the delegated checked payload discarded.

### What was pleasant

The whole selection was one constructor away: `checkedIfEmpty` is
`hiddenIfEmpty` with the property name flipped, so the model, the
rewrite, the sweep, and the mount block all extended by pattern-match
arms over shapes that already existed — the `regionSubject?` /
`regionPredicate?` accessors even unified the two selections' sweep
lowering into one code path, deleting the hidden-specific names from the
backend. The payload-less change binding cost nothing at the host: the
plain `listen` export a click binding uses already delivers the change
event, and the elaborator only had to stop insisting that `change`
resolve a typed value event when the named event is plain. The
duplicate-property guard fell out of the existing LRX-VIEW-021 check by
appending the selection names to the prop names.

### Friction encountered

The uncheck gesture is a genuine trap the gate now documents: clicking
the checked box fires `completeAll`, whose equal-value broadcast changes
no row, so the sweep sees no flip and leaves the cache true while the
browser keeps the user's visual uncheck — the DOM and the cache disagree
until the next region touch. That divergence is the honest boundary of
the display half, pinned as an evaluate-only step with the DOM reading
false. And the artifact gate's long sweep pin had to absorb the checked
scan inside the same `if (region_touched_0)` block — the pinned string is
now three subjects long, which is the price of pinning the sweep as one
literal.

### Bugs found

No framework defect surfaced: the forged model gates (accepted predicate
and total checked selections with their `select:checked:r:0:x` /
`select:checked:r` debug markers, boolean value type, and graph
exclusion; the unknown-region and out-of-bounds LRX-VIEW-042; the
non-checkbox rejections and the controlled-beside-selection
LRX-VIEW-021), the three new compile-fail fixtures (threshold
LRX-ELAB-125, unknown field LRX-ELAB-119, non-checkbox LRX-VIEW-043),
the updated elaborator, artifact, and guide gates, and all Toggle Lab
browser gates (the three new ADR-0060 gates included) passed.

### Performance observations

Byte-diff proof under the performance freeze: every file of every other
lab and of the js-framework-benchmark bundle — `main.mjs` and manifest
included — is byte-identical to the HEAD baseline (full before/after
builds into the scratchpad); only Toggle Lab's module, manifest (gaining
`region-checked`), and graph (source spans only — the selection joins no
graph node) change. A checked selection costs one row-table scan per
region-touching transaction — the ADR-0050 count-text cost, and only
there: a filter change skips it entirely — and the boolean cache keeps
every non-flip write-free: the browser gates pin the not-done append and
the completeAll broadcast as one evaluation and one write each, and the
clearCompleted vacuous truth as one evaluation and zero writes.

### Follow-up issue or commit

`feat(component): reflect the region count into the toggle-all checkbox
(ADR-0060)`, `test(component): forge the region-checked gates and teach
the guide`, and `docs(adr): accept the region-checked reflection
(ADR-0060)`. Remaining gaps carried forward: toggle-all phase 2 (a
delegated checked payload flowing into a component-scope broadcast —
`event toggleAll (checked : String) := update items (set done checked)` —
the ADR-0050 broadcast only carries sealed row expressions) is the next
round's candidate; the component-scope Escape arm is sealed but unproven
(no new-todo revert contract exists to prove it); affordance-contract
agreement stays ADR-0059's first open question; the ADR-0050 predicate
removal, ADR-0051 filter arms, ADR-0044 row class selection, and
ADR-0049 row checked reflection still compare raw fields; the guard
literal is sealed at the empty string; row guards stay single-field
remove-or-commit; the key set stays sealed at Enter/Escape; `s!`
interpolation absent from row scope; branch cells single-level and
two-branch with exact click/dblclick agreement; child instrumentation
still unreachable through the parent disposer; and the items-left
singular/plural text ("1 item left") stays an unexpressed candidate.

## Payload broadcast — toggle-all phase 2

### Scenario exercised

The ADR-0061 round: TodoMVC's toggle-all action closed both ways with no
host change and no ABI bump. The one missing sentence — a typed component
event whose payload flows into a region broadcast — shipped as
`event toggleAll (checked : Bool) := update items (set done checked)`:
the payload identifier is admitted as a bare `set` right-hand side of the
ADR-0050 broadcast, the delegated checked boolean lowering to the
`"true"`/`"false"` strings exactly as the ADR-0049 row payload does.
Toggle Lab's box rebound from the ADR-0060 payload-less
`onChange={completeAll}` to `onCheckedChange={toggleAll}` — the ADR-0038
surface through the existing `listenChecked` export — so checking the box
completes every row and unchecking it un-completes every row: the sweep's
evaluate-compare-write now agrees with the browser's own uncheck, and the
pinned ADR-0060 cache-DOM divergence gate is replaced by parity gates.
The model carries the event as the new `AnyTypedEvent.boolBroadcast`
constructor validated under `LRX-TYPE-116` (declared region, nonempty
distinct in-bounds assignments, bare payload written at least once);
the surface seals under `LRX-ELAB-126` (Bool-only payload, no
composition); and the vocabulary decisions are recorded as rejections —
String payload direct, payload composition, payload in any non-broadcast
position, an `onChange={toggleAll}` overload, and retiring the ADR-0060
payload-less binding all declined.

### What was pleasant

The composition really was the whole feature: the broadcast emission
factored into one shared `regionBroadcastStmts` helper whose plain caller
passes the inert string and whose typed caller passes
`checked ? "true" : "false"` — byte-identical output for every existing
component, verified by full before/after builds (only Toggle Lab's three
files change, spans included). The ADR-0038 machinery needed zero
changes at the binding layer: `onCheckedChange` already lowered to the
checked-change kind, `acceptsPayload` gained one constructor arm, and
`listenChecked` already delivered exactly the boolean the broadcast
needs. Keeping `TypedEventSpec`/`ParamUpdate` untouched (a third
`AnyTypedEvent` constructor instead) meant the Form milestones' total
`target` accessors never noticed the round.

### Friction encountered

The accessor totality was the real design fork: extending `ParamUpdate`
with a broadcast constructor would have made `TypedEventSpec.target`
partial and rippled into the Form milestones, so the round settled on the
separate `boolBroadcast` spec — the right call, but it took a survey of
every `targetIndex`/`target` consumer to see it. Validation order
mattered for error quality: the bare-payload composition check has to run
before the "never writes its payload" check, or `set done (trim checked)`
reports the misleading missing-payload message. And the vacuous-truth
caveat survives on the empty region: unchecking the empty box broadcasts
over zero rows and the checked subject stays vacuously true, so the cache
keeps true while the DOM keeps the gesture — pinned as the no-op gate,
honest but still a whisper of the old divergence in the one state TodoMVC
never shows (the real app hides the box when the list is empty; the
hidden-when-empty candidate is noted below).

### Bugs found

No framework defect surfaced: the forged model gates (accepted payload
broadcast with its empty summary and checked-change resolution, the
LRX-VIEW-018 value-binding rejection, and the six-member LRX-TYPE-116
family), the three new compile-fail fixtures (String payload and composed
payload LRX-ELAB-126, unknown field LRX-ELAB-115), the updated
elaborator, artifact, and guide gates, and all Toggle Lab browser gates
(the rewritten both-way parity gate and the two new ADR-0061 gates
included) passed. The only iteration was the environment audit: the new
constructor's generated `injEq` theorems needed their two reviewed
propext entries.

### Performance observations

The performance freeze held by construction: every file of every other
lab and of the js-framework-benchmark bundle is byte-identical to the
HEAD baseline (full before/after builds into the scratchpad); only
Toggle Lab's module, manifest (gaining `payload-broadcasts` and one
event), and graph (source spans only) change. A payload broadcast costs
exactly a plain broadcast: the same per-row evaluate-then-assign loop,
the same dirty reconcile over retained rows, the same one-scan-per-touch
sweep — the browser gates pin the joint update as one transaction (two
retained-row updates, one evaluation per selection, one checked write),
the equal-payload broadcast as evaluate-only, and the empty-region
broadcast as metric-preserving.

### Follow-up issue or commit

`feat(component): flow the checked payload into the region broadcast
(ADR-0061)`, `test(component): forge the payload-broadcast gates and
teach the guide`, and `docs(adr): accept the payload broadcast
(ADR-0061)`. Remaining gaps carried forward: the component-scope Escape
arm is sealed but unproven (no new-todo revert contract exists to prove
it); affordance-contract agreement stays ADR-0059's first open question;
the ADR-0050 predicate removal, ADR-0051 filter arms, ADR-0044 row class
selection, and ADR-0049 row checked reflection still compare raw fields;
the guard literal is sealed at the empty string; negated and composite
subjects stay rejected; row guards stay single-field remove-or-commit;
the key set stays sealed at Enter/Escape; `s!` interpolation absent from
row scope; branch cells single-level and two-branch with exact
click/dblclick agreement; child instrumentation still unreachable through
the parent disposer; the items-left singular/plural text ("1 item left")
stays an unexpressed candidate; and TodoMVC's hide-the-toggle-all-chrome
refinement (the toggle-all box and footer riding the ADR-0058 emptiness
subject) is expressible today but unexercised in Toggle Lab.

## Count label — the items-left grammar

### Scenario exercised

The ADR-0062 round: TodoMVC's items-left singular/plural text ("1 item
left") closed as a sealed count-driven text selection with no host change
and no ABI bump. `{if count items (done == "false") == 1 then " item
left" else " items left"}` is a text position comparing the ADR-0050
count subject — total or predicate — against the one literal and
selecting between two static strings. The surface rides the same
component-command rewrite the count children and the visibility subjects
use (internal `regionCountLabel%` child), the model carries the label as
the optional string pair on `View.regionCount`/`MountedRegionCount`
under the unchanged `LRX-VIEW-038` obligations, and the backend gives the
label one more count slot: mounted at the `else` string (an empty region
counts zero, and zero differs from one) with the cache slot mounting the
same string, recomputed on the region-touch sweep with the same per-slot
scan every count runs (no scan sharing — ADR-0050 already re-scans per
position), and written through the existing `setText` export only on a
singular/plural flip. Toggle Lab's items-left line now reads
`<strong>N</strong>{label} of {total}`, and the guide's
`CountedRosterMini` teaches the same shape. The vocabulary decisions are
recorded as rejections — threshold generalization, negation and
composition, non-count subjects, dynamic strings, a separate keyword
surface, and a label-specific host export all declined (`LRX-ELAB-127`
for the count-headed violations, `LRX-VIEW-012` for everything else).

### What was pleasant

The label really was one slot away: the mounted count inventory, the
region record's ref/cache slots, the touched flag, and the sweep loop all
took the label as one more entry, so the whole backend delta is a
three-line value selection between the recomputed count and the cache
compare — the numeric slots emit byte-identically, which is what kept
every other lab and the benchmark bundle byte-identical under the freeze.
The count-headed rewrite pattern from ADR-0058/0059/0060 transferred
verbatim to the child position: claim the `count` head, seal the literal,
resolve the region and field where the inventory exists.

### Friction encountered

Two knife-edges, both caught by gates. Adding the label field to the
`View.regionCount` constructor touched every `.regionCount _ _ _`
pattern in the mutual view traversals — Lean fills omitted default-valued
constructor arguments in patterns with the defaults, not wildcards, so
each arm needed its explicit fourth argument (the standing audit note).
And the label text node shifted Toggle Lab's mount numbering (the ul and
the toggle-all box moved from node_25/node_26 to node_26/node_27), which
the artifact gate pinned across a dozen required strings — mechanical,
but a reminder that the gate pins document order on purpose. The
environment audit needed one new reviewed entry: `MountNode.countText`
gained arguments, so its generated `injEq` theorem now uses propext.

### Bugs found

None in the host or the dispatcher. The pre-change divergence was purely
expressive: the singular flip was unrepresentable, and the items-left
line read a lab-specific "N left of M" instead of TodoMVC's grammar.

### Performance observations

The performance freeze held by construction: every file of every other
lab and of the js-framework-benchmark bundle is byte-identical to the
HEAD baseline (full before/after builds into the scratchpad); only
Toggle Lab's module, manifest (gaining `count-labels`), and graph
(source spans only) change. A label count costs exactly a predicate
count — one scan per region-touching transaction — and the browser gates
pin the flip economics: one evaluation and one write on the first
append's singular flip, one more write on the plural return, evaluate-only
on an equal selection, and no evaluation at all on a filter change.

### Follow-up issue or commit

`feat(component): select the items-left label from the region count
(ADR-0062)`, `test(component): forge the count-label gates and teach the
guide`, and `docs(adr): accept the count label (ADR-0062)`. Remaining
gaps carried forward: the component-scope Escape arm is sealed but
unproven (no new-todo revert contract exists to prove it);
affordance-contract agreement stays ADR-0059's first open question; the
component-scope payload reaches one construct (guards, appends, key arms,
and filter predicates stay payload-blind, ADR-0061's second open
question); the ADR-0050 predicate removal, ADR-0051 filter arms, ADR-0044
row class selection, and ADR-0049 row checked reflection still compare
raw fields; the guard literal is sealed at the empty string; negated and
composite subjects stay rejected; row guards stay single-field
remove-or-commit; the key set stays sealed at Enter/Escape; `s!`
interpolation absent from row scope; branch cells single-level and
two-branch with exact click/dblclick agreement; child instrumentation
still unreachable through the parent disposer; the two-threshold count
grammar ("no items"/"1 item"/"N items") stays rejected as ADR-0062's
second open question; and TodoMVC's hide-the-toggle-all-chrome
refinement (the toggle-all box and footer riding the ADR-0058 emptiness
subject) is expressible today but unexercised in Toggle Lab.

## Empty-list chrome and Escape revert — a lexicon-invariant round

### Scenario exercised

An execution round, not an ADR: two contracts the sealed vocabulary
already carried but Toggle Lab had never run. First, TodoMVC's
main/footer hide-when-empty parity — the toggle-all checkbox takes
`hidden={count items == 0}` beside its existing `checked` selection, and
the items-left line plus the three filter buttons move into a
`<footer hidden={count items == 0}>` after the list. Both are the
ADR-0058 emptiness subject reused verbatim on two more attr slots:
`HtmlTag.footer` already existed, the ADR-0045 duplicate detection keys
on the attribute name (so `checked` and `hidden` coexist on one
element), and the `hiddenIfEmpty` selection was already valid on any
static element. Second, the new-todo Escape revert — `confirmAdd` gains
`then when "Escape" (set draft "")`, executing the Escape half of the
ADR-0056 sealed Enter/Escape component key set that had been spellable
but unproven. The arm is unguarded, so it pins the unconditional-commit
path: Escape clears the draft, the controlled input follows through the
ADR-0038 reflection, the Add button re-disables through its ADR-0057
selection in the same commit, and a subsequent Enter hits the ADR-0055
skip guard as a whole-event no-op. No elaborator, model, backend, or
host file changed — the diff is the lab source, the gates, and this
record. No host change, no runtime ABI bump.

### What was pleasant

The claim "expressible today" was literally true: the lab edit was three
lines of view and one arm, and the generator produced the right code on
the first build. The attr slot economics composed without any new
machinery — the two new emptiness slots joined the same region-touch
sweep block, each with its own evaluation, cache compare, and flip-only
write, so the browser gates could pin "one commit reveals wrapper, box,
and footer together" as three `+1` label counts. Placing the footer
last in document order kept every existing `attr:N` label stable
(attr:0..3 unchanged, attr:4/attr:5 purely additive), which cut the
expected gate churn roughly in half.

### Friction encountered

The chrome hiding is honest — and that honesty broke tests. Playwright's
role queries exclude hidden elements, so every gate that addressed the
toggle-all box or a filter button while the region was empty had to
switch to id locators or synthetic clicks (the ADR-0051 appended-rows
gate sets the completed filter before the first append, which a real
user can no longer do — the dispatch, not the affordance, carries the
contract, so the gate clicks the hidden button synthetically). Moving
the items-left line and the filter buttons into the footer renumbered
the mount nodes again (ul and toggle-all moved from node_26/node_27 to
node_14/node_15), which the artifact gate pinned across the usual dozen
strings — document order is load-bearing and the gate says so.

### Bugs found

None. The duplicate-detection question the round was asked to settle —
does `hidden` beside `checked` on one element collide? — resolved by
reading `validateView`: both checks key on attribute/property names, and
the two selections carry different names, so the element passes both
LRX-VIEW-001 and LRX-VIEW-021 by construction.

### Performance observations

The freeze held by construction: no compiler or host file changed, so
every other lab and the benchmark bundle are byte-identical trivially;
the codegen determinism check passed over the full example set. The new
chrome costs two more `length === 0` reads per region-touching commit —
no scan, the subject is the row-table length — and a filter change alone
still evaluates nothing (pinned per slot in the browser gates). Escape
costs one transaction with one string write, and the equal-value Escape
(draft already empty) commits with the changed flag down: no prop write,
no attr evaluation.

### Follow-up issue or commit

`feat(component): execute the empty-list chrome and Escape revert in
Toggle Lab` and this record. With this round, Toggle Lab's TodoMVC
interaction parity has two gaps left, and both need host exports under
the freeze: URL routing (`#/active` sync) and localStorage persistence.
Remaining gaps carried forward: affordance-contract agreement stays
ADR-0059's first open question; the component-scope payload reaches one
construct (ADR-0061's second open question); the count label stays
text-position-only with the one literal sealed and the two-threshold
grammar rejected (ADR-0062's open questions); the ADR-0050 predicate
removal, ADR-0051 filter arms, ADR-0044 row class selection, and
ADR-0049 row checked reflection still compare raw fields; the guard
literal is sealed at the empty string; negated and composite subjects
stay rejected; row guards stay single-field remove-or-commit; branch
cells single-level and two-branch with exact click/dblclick agreement;
child instrumentation still unreachable through the parent disposer. The
next-next round should be an ADR weighing the freeze-compatible residue
(unifying the raw-field comparisons, revisiting attribute-position count
labels) against lifting the freeze for routing and persistence.

## The freeze boundary — a decision round (ADR-0063)

### Scenario exercised

A decision round, not an execution round: with routing and persistence
the only TodoMVC interaction gaps left and both needing host exports,
ADR-0063 weighed the freeze-compatible residue (unifying the five
spellings of the single-field-literal equality, re-opening
attribute-position count labels, affordance-contract checking) against
the exports, and took the parity axis — five sealed DOM-host exports
(`readHash`, `listenHash`, `writeHash`, `storageGet`, `storageSet`) as
one runtime ABI 17 round, execution deferred to the next round. Routing
seals onto the routed state field (the ADR-0045/0051 filter field);
persistence seals onto the declared region row table via the
region-touch sweep. The diff is the ADR, the DECISIONS row, one stale
sentence repaired in `runtime-representation.md`, and this record.

### What was pleasant

The freeze turned out to have a surveyable boundary rather than a
mood. The size gate measures exactly `index.html` and `main.mjs`, the
benchmark module carries no ABI byte, and the compactor prunes
unreachable host functions before renaming — so ADR-0048's "byte
identical, manifest number only" was not a lucky outcome but the
mechanism, and ABI 17 inherits it as three written conditions
(reachability-gated imports, no non-literal module-level bindings in
the host, no compactor-rejected constructs). The residue survey was
equally concrete: seven backend lowerings, six elaborator resolutions,
nineteen validator bounds checks, five model spellings of one concept,
with the byte-neutral unification scope (comparison builder yes, scan
loops no — the golden ident prefixes pin the loops) recordable in
advance.

### Friction encountered

The survey caught two debts from the ABI 16 fan-out: `check_cli.sh`'s
doctor literal had been missed then and fixed a round late, so the
ADR-0063 checklist names it explicitly; and
`runtime-representation.md` still said "currently version 15" two
sections above its own ABI 16 paragraph — repaired in this round since
the fix is documentation. The count of mechanical bump sites is 24
literals plus two docs, not the folklore ~25 — close enough that the
folklore never got audited.

### Bugs found

One documentation staleness bug (the "version 15" sentence), fixed.
No code bugs; no code was touched.

### Performance observations

Docs only: every lab and the benchmark bundle are byte-identical by
construction and the full gate suite runs against unchanged code. The
freeze holds with nothing to verify; the next round owes the size gate
its green under the three ADR-0063 freeze conditions.

### Follow-up issue or commit

`docs(adr): take the parity axis at the freeze boundary (ADR-0063)`
and this record. Next round executes ABI 17: the five exports, the
sealed route item and storage key, the 24-literal fan-out, unit gates
beside the DOM-host helpers, compile-fail fixtures, and the Toggle Lab
browser gates (hash seed, hashchange dispatch, flip-only writeHash,
hydration, per-touch persistence). Remaining gaps carried forward: the
`FieldPredicate` unification stays open with its byte-neutral scope
recorded; affordance-contract agreement stays ADR-0059's first open
question; the component-scope payload reaches one construct
(ADR-0061); the count label stays text-position-only with the one
literal sealed and the two-threshold grammar rejected (ADR-0062);
attribute-position count labels stay rejected; negated and composite
subjects stay rejected; the guard literal stays `""`; row guards stay
single-field remove-or-commit; row scope still has no `s!`; branch
cells stay single-level two-branch with exact click/dblclick
agreement; child instrumentation stays unreachable through the parent
disposer.

## Routing and persistence — the ABI 17 execution round (ADR-0063)

### Scenario exercised

The ADR-0063 execution round: the last TodoMVC interaction parity axis
closed as one runtime ABI 17 bump adding five sealed DOM-host exports —
`readHash`, `listenHash`, `writeHash`, `storageGet`, `storageSet` —
under the ADR-0048 pruning condition. The sealed route item (`route
filter := when "#/" "all" then when "#/active" "active" then when
"#/completed" "completed"`) seeds the filter field from the hash at
mount, dispatches every hashchange through the same set-field commit
the filter buttons run, and writes the canonical hash flip-only behind
the field's changed flag. The sealed persist item (`persist items :=
"leanrx-toggle-lab.items"`) hydrates the region row table at mount
through one ordinary transaction riding the existing append path and
re-persists once per region-touching sweep on the shared touched flag;
a filter change alone persists nothing. Serialization is a throw-free
split/join escape in generated code; the hosts move strings only.

### What was pleasant

Two shells did almost all the work. Emitting the route arms and the
hydration as ordinary `transactionShell` functions meant the filter
sweep, the count labels, the visibility slots, the flip-only hash
write, and the normalized storage write-back all ran at mount and on
every hashchange with zero new commit machinery — hydration is
literally an append-shaped transaction, so "rows, counts, chrome, and
filter settle together" was true by construction on the first
successful build. The freeze conditions held exactly as ADR-0063
surveyed: the size gate came back green with `main.mjs` byte-identical
on the first run, no benchmark re-run owed.

### Friction encountered

Three small snags. `let key ←` in the elaborator collided with a
declared token and had to be renamed (`storageKey`). The nested
validator chain in `ComponentSpec.check` needed a full re-indentation
to splice two more arms in — Lean's match-arm indentation is
unforgiving inside eleven nested matches. And binding the found
`RegionFilter` through `←` inside the route validator tripped a
universe mismatch (`RegionFilter Γ : Type 1` inside the `Except`
do-block's `forIn`), solved by projecting the needed pair
(`filter.arms.map (·.1), filter.span`) instead of the structure. One
audit-list debt surfaced exactly as the memory predicted: the new
structures' `injEq` theorems had to join the reviewed axiom manifest.

### Bugs found

None in shipped code. The design dodged two latent ones deliberately:
`decodeURIComponent` would have made a hand-edited stored value throw
at mount (the split/join escape cannot throw), and a bare
`location.hash` writer would have echoed if WHATWG equal-value
assignments fired hashchange — the browser gate pins the echo settling
at exactly one route write.

### Performance observations

The benchmark bundle is byte-identical (size gate green, manifest
`runtimeAbi` number only), so the freeze holds with nothing re-run —
regression watch only. Every other lab emits byte-identical modules;
the Toggle Lab module grows by the three route arm transactions, one
dispatch, one hydrate transaction, and the per-shell route/persist
ride. Persistence costs one serialization pass per region-touching
commit — linear in the row table, same order as the count scans that
already ride the touched flag.

### Follow-up issue or commit

`feat(component): execute routing and persistence as runtime ABI 17
(ADR-0063)` — the five host exports, the sealed `route`/`persist`
items, the 24-literal fan-out (doctor line included this time), the
"ABI 17 adds …" section, five compile-fail fixtures, real-DOM host
gates in counter.spec.mjs, and seven Toggle Lab browser gates. With
this round closed, Toggle Lab's TodoMVC interaction parity has no
known remaining gap. Remaining gaps carried forward: the
`FieldPredicate` unification stays open with its byte-neutral scope
recorded (comparison builder only, scan loops excluded — golden ident
prefixes pinned); affordance-contract agreement stays ADR-0059's first
open question; the component-scope payload reaches one construct
(ADR-0061); attribute-position count labels and the two-threshold
grammar stay rejected (ADR-0062); negated and composite subjects stay
rejected; the guard literal stays `""`; the count-label literal stays
one; row guards stay single-field remove-or-commit; row scope still
has no `s!`; branch cells stay single-level two-branch with exact
click/dblclick agreement; child instrumentation stays unreachable
through the parent disposer.

## Field-predicate unification — the ADR-0063 hygiene round (ADR-0064)

### Scenario exercised

The deferred byte-neutral residue of ADR-0063, executed exactly as its
Context fixed it: a named `FieldPredicate` (a `RowExpr` subject plus
the compared literal) introduced beside `RowExpr`; four of the five
spellings joined at the model (`RowGuard` replaced outright,
`RowClassSelect` and `Update.regionRemoveIf` storing the predicate,
`RegionFilter.arms` carrying `(String × FieldPredicate)`); the seven
hand-rebuilt `.binary .eq (item[field + 1]) ("literal")` backend
subtrees — plus the two sites that already lowered subjects through
`rowExprJs` and hand-appended only the equality — replaced by one
`fieldPredicateJs` builder; and the nineteen near-identical
out-of-bounds validator blocks folded into one `checkFieldBound` rule
with every error code and message string preserved verbatim. Scan
loops stayed duplicated on purpose: `count_scan_*`, `hidden_row_*`,
`kept_*`, and `row_guard` are golden identifier contracts.

### What was pleasant

Byte-neutrality really was "by construction": `rowExprJs (.field i)`
produces exactly the subtree the seven sites hand-built, so routing
them through the builder could not move a byte, and the artifacts
gates confirmed it without a single golden-snippet edit — `git status`
showed no generated `.mjs` or manifest change at any point. The
nineteen bounds messages turned out to share one exact sentence shape
(`"… field {i} outside region {name}'s {n} field(s)"` with the region
name always equal to the `find?`-resolved `region.name`), so the
helper preserves every message byte-for-byte while deleting ~90 lines
of throw blocks. And `RowGuard` being structurally identical to the
new predicate meant the language-guide test's anonymous
`some ⟨.trim (.field 1), ""⟩` spellings compiled unchanged.

### Friction encountered

Small and predictable. The five spelling changes rippled into exactly
the places the survey predicted — one elaborator quotation each, the
Lean-side test literals, and the audit manifest's `injEq` entry
(`RowGuard.mk.injEq` → `FieldPredicate.mk.injEq`) — plus one missed
test literal (`#[("r", 2, [("odd", 0, "x")])]`) that the first build
caught immediately. The removal-target assertions changed type
(`(String × Nat)` → `(String × FieldPredicate)`), which is strictly
stronger: the old pair silently dropped the compared literal.

### Bugs found

None. The one design question — storing a `RowExpr` subject where a
`Nat` sat makes non-field subjects representable at the model level —
was resolved by precedent rather than new machinery: the ADR-0049
reflect subject has always had exactly this representability, the
elaborator is the only producer and only emits `.field`/`.trim
(.field i)` there, and the validator bounds-checks every field
reference either way. ADR-0064 names the trade instead of hiding it.

### Performance observations

Nothing to measure: every lab and the benchmark bundle emit
byte-identical JavaScript, the size gate passed against the unchanged
baseline, and no manifest moved — no ABI bump, freeze intact,
regression watch only.

### Follow-up issue or commit

`refactor(component): unify the field predicate as one sealed spelling
(ADR-0064)` — the model/backend/validator consolidation, the updated
Lean-side assertions, ADR-0064, and the DECISIONS row. The invariants
hold: the key set stays sealed at Enter/Escape; the guard literal
stays `""`; the count-label literal stays one; row guards stay
single-field remove-or-commit; row scope still has no `s!`; branch
cells stay single-level two-branch with exact click/dblclick
agreement; child instrumentation stays unreachable through the parent
disposer.

## Route and persist in the language guide — a guide-teaching round

### Scenario exercised

A documentation-and-gate round in the lexicon-invariant precedent: no
ADR, no code, no manifest, no generated byte moved. The ADR-0063
route/persist surfaces the ABI 17 round executed were taught to
`docs/guides/language.md` as two new section-7 clauses in the existing
convention (prose with inline error codes plus a compiled snippet):
the `route field := when "#/hash" "literal" then …` clause — the 1:1
sealed table over the declared ADR-0051 filter field, exactly one arm
on the declared default so the unknown-hash fallback is a table entry,
`hashchange` dispatching the same set-field commit as the filter
buttons, flip-only `writeHash` (`LRX-ELAB-128`/`LRX-TYPE-117`) — and
the `persist region := "storage-key"` clause — one sealed literal key
per component, the throw-free `%`/`,`/`;` split/join escape,
fail-closed hydration as one ordinary transaction through the existing
append path, one `storageSet` per region touch with a filter change
persisting nothing (`LRX-ELAB-129`/`LRX-TYPE-118`). The stale
section-10 "LeanRx does not currently provide a URL router" sentence
was corrected to the sealed-route-table statement, and the same stale
claim was found and minimally corrected in `backend-support.md`'s
unsupported list and `dogfood-case-studies.md`'s self-hosting entry.
Both snippets compile in `Test/Docs/LanguageGuide.lean` in the
CountedRosterMini convention: `RoutedRosterMini` asserts the route arm
table and the filter arms' ADR-0064 `FieldPredicate.ofField` spelling;
`PersistedRosterMini` asserts the sealed storage key and the
`regionRemoveIfTargets` predicate spelling.

### What was pleasant

The guide's clause convention absorbed both surfaces without any new
structure: the filter clause already established the `when`-table
prose shape, so the route clause reads as its hash-keyed sibling, and
the ADR-0063 open-question resolutions contained every sentence the
clauses needed — nothing had to be re-derived from the elaborator. The
gate additions were pure pattern-following: the `FilteredRosterMini`
match arm gave the route assertion its exact shape, and the ADR-0064
unification meant the new assertions pin the *stronger* predicate
spelling (`.ofField 1 "true"` carries the compared literal the old
`(String × Nat)` pairs dropped) for free.

### Friction encountered

Only namespace hygiene: the test file's snippet fields live in one
namespace, so the guide's natural `shown`/`filter` names were already
taken by earlier snippets and the new schemas spell `routedShown`/
`persistedAdded` — the same renaming every snippet since
`FilteredRosterMini` has paid. The dogfood-case-studies correction
needed a tense split rather than a deletion: the self-hosting entry
records what was true then, so it now says "at the time there was no
URL router" with the ADR-0063 narrowing in apposition instead of
rewriting history.

### Bugs found

None in code — the round touched none. Three stale-prose defects were
found and fixed: the language guide's section-10 router sentence, the
backend-support unsupported list's unqualified "URL router/history
integration" line, and the case-study's present-tense "there is no URL
router".

### Performance observations

Nothing to measure and nothing measured: the diff is two guide
snippets compiled into the test module plus markdown, `git status`
shows no generated `.mjs` or manifest change, and the benchmark bundle
is untouched — freeze intact, BENCHMARK.md numbers stand, regression
watch only.

### Follow-up issue or commit

`docs(guide): teach the sealed route and persist surfaces (ADR-0063)`
— the two language-guide clauses, the three stale-router corrections,
and the two compiled snippet gates. The invariants hold: the key set
stays sealed at Enter/Escape; the guard literal stays `""`; the
count-label literal stays one; row guards stay single-field
remove-or-commit; row scope still has no `s!`; branch cells stay
single-level two-branch with exact click/dblclick agreement; child
instrumentation stays unreachable through the parent disposer.

## The Toggle Lab parity arc as a case study — a docs round

### Scenario exercised

A documentation-only round in the guide-teaching precedent: no ADR, no
code, no manifest, no generated byte moved. The Toggle Lab
component-command TodoMVC parity arc (ADR-0043..0064, ABI 16 and 17)
was taught to `docs/guides/dogfood-case-studies.md` as a new section
after the original TodoMVC entry, in the existing convention (short
paragraphs, `DOGFOOD.md` pointer): the sealed-vocabulary accumulation
— keyed regions/immutable props → typed row events → branch cells →
row focus → delegated dblclick/checked → counts/broadcasts/removeIf →
filter views → row and component key branching → remove-if/skip-if
guards → trim → hidden/checked/disabled attribute selections → count
label → route/persist — that closed interaction parity across
twenty-two ADRs and two runtime ABI bumps, and the two cross-cutting
lessons: the sealed-surface extension convention (exactly one parity
contract per round, speculative vocabulary rejected on the record) and
reachability-gated host extension under the byte-identical freeze
(ADR-0048/0063 precedent). The original TodoMVC section gained one
sentence marking it as a handwritten-backend-era case. The stale
survey over `architecture.md`, `tooling.md`, and `trust-model.md`
found no route/persist/ABI-17/FieldPredicate staleness — all three
state ABI facts version-agnostically and trust-model's storage line is
a TCB enumeration — so no correction was made.

### What was pleasant

The arc summarized itself: every clause in the new section is the
title line of an existing DOGFOOD entry or an ADR decision sentence,
so the case study is an index, not new analysis. The case-study file's
section convention (one scenario paragraph, one lessons paragraph)
absorbed a twenty-two-ADR arc without strain because the arc's own
discipline — one contract per round — made the accumulation listable
in a single sentence.

### Friction encountered

Only one wording decision: the existing TodoMVC section describes a
still-passing app, so marking it stale would be wrong — the added
sentence says it *predates* the component-command surface rather than
deprecating it, matching the tense-split treatment the self-hosting
entry received last round.

### Bugs found

None, and no stale prose either: the three-guide survey came back
clean, which is itself evidence the last two rounds' corrections
covered the surface.

### Performance observations

Nothing to measure and nothing measured: the diff is markdown only,
no generated `.mjs`, manifest, or size-gate input changed, and the
benchmark bundle is untouched — freeze intact, BENCHMARK.md numbers
stand, regression watch only.

### Follow-up issue or commit

`docs(dogfood): teach the Toggle Lab parity arc as a case study` — the
new case-study section, the one-sentence era marker on the original
TodoMVC entry, and this record. The invariants hold: the key set
stays sealed at Enter/Escape; the guard literal stays `""`; the
count-label literal stays one; row guards stay single-field
remove-or-commit; row scope still has no `s!`; branch cells stay
single-level two-branch with exact click/dblclick agreement; child
instrumentation stays unreachable through the parent disposer.

## Affordance-contract alignment — a decision round (ADR-0065)

### Scenario exercised

A decision round on the checkability axis: the "affordance is not the
contract" open question ADR-0059 OQ1 and ADR-0061 OQ1 have carried
since the Add-button round. The survey covered every
affordance-contract pair Toggle Lab can spell — the hidden
clear-completed button against the ADR-0050 predicate removal, the
checked toggle-all reflection against the ADR-0061 payload broadcast,
the disabled Add button against the ADR-0055 skip guard — asking for
each how the two predicates sit in the sealed model, which layer could
compare them, and whether legal programs would be rejected. ADR-0065
records the answer: rejected, as an error and as a warning; the
dispatch layer stays the one contract.

### What was pleasant

The ADR-0064 unification made the survey mechanical: with
`FieldPredicate` deriving `DecidableEq` and
`regionRemoveIfTargets` carrying the whole predicate, pair A's
comparability was a one-glance fact, and the two non-joiners (the
anonymous count/hidden pair, the unstored guard literal) named exactly
where normalization would have to happen. The mounted split answered
the layer question the same way — `MountedAttrSelect` and
`MountedEvent` both carry element paths, so co-location is computable
in `ComponentSpec.check` today — which let the rejection rest on
representability and over-rejection rather than on any claimed
implementation difficulty.

### Friction encountered

None mechanical. The one conceptual snag was productive: the toggle-all
input itself is the counterexample to the obvious pairing rule — it
co-locates a predicate-free `hidden` selection with a predicate-free
broadcast binding, so a co-location checker needs a selection-kind ×
event-kind compatibility table before its first comparison, and that
table is the speculative vocabulary the convention rejects.

### Bugs found

None. The survey confirmed the three pairs sit in the model exactly as
their ADRs recorded them, and turned up one structural fact worth
naming: the meaningful half of the toggle-all alignment lives in the
value alphabet of an uninterpreted string field — no checker over the
current model can certify it, only suggest it certifies it.

### Performance observations

Nothing to measure and nothing measured: the diff is markdown only —
the ADR, the DECISIONS.md row, and this record — no generated `.mjs`,
manifest, or size-gate input changed, and the benchmark bundle is
untouched. Freeze intact, BENCHMARK.md numbers stand, regression watch
only.

### Follow-up issue or commit

`docs(adr): reject the affordance-contract alignment check (ADR-0065)`
— the survey-and-rejection ADR, the DECISIONS.md row, and this record.
ADR-0059 OQ1 and ADR-0061 OQ1 are closed, not carried; future
affordance rounds inherit "presentation policy, free to differ" as a
decided invariant. The invariants hold: the key set stays sealed at
Enter/Escape; the guard literal stays `""`; the count-label literal
stays one; row guards stay single-field remove-or-commit; row scope
still has no `s!`; branch cells stay single-level two-branch with
exact click/dblclick agreement; child instrumentation stays
unreachable through the parent disposer.

## Child instrumentation reachability — a decision-and-execution round (ADR-0066)

### Scenario exercised

The oldest carried invariant fell due for a decision: ADR-0039 phase 1
left "the child's instrumentation is not reachable through the parent
disposer" as future work, and every round since restated it. The
survey walked the whole `<Child/>` disposer path in the generated
artifacts: NestLab turned out to be the *only* child-composing module
(EchoLab shares the component gates but composes nothing, and no bench
source has a capitalized child head), the child mount return —
dispose closure plus all three instrumentation accessors — joins the
parent's `makeDisposer` listener list and nothing else, and the
dispose-time splice erases even that. ADR-0066 adopts reachability as
the one contract: child-composing modules emit
`disposer["children"] = [child_off_0];` between the disposer
construction and the return, republishing the child mount returns in
declaration order. Counter merging and a host-side accessor are
rejected in the same ADR.

### What was pleasant

The representability question answered itself from the AST: `Expr` has
no function form, so the aggregating-accessor design was dead on
arrival without a host change — which the freeze forbids — and the
one representable spelling (`Stmt.assign` on an index target) was also
the best design. Because the array element *is* the child's mount
return, every facet — `instrumentation()`, `regionInstrumentation()`,
even a future grandchild's `children` — composes transitively with
zero new vocabulary. The `dom.childOffs.isEmpty` guard made the freeze
argument structural: one line in NestLab.mjs is the entire generated
diff in the repository, and every manifest is byte-identical.

### Friction encountered

None mechanical. The one design snag was the affordance question:
republishing the child disposer also republishes early disposal. The
ADR-0065 invariant resolved it cleanly — the child's mount return is
already the child module's public ABI and its `disposed` flag already
makes calls idempotent, so the parent adds reachability, not
semantics; an affordance, not a contract.

### Bugs found

None. The survey confirmed disposal chaining itself was always correct
(the splice calls the child disposer, idempotently), so the gap was
purely observational — exactly the kind of gap the instrumentation
surface exists to close.

### Performance observations

Frozen by construction: the benchmark bundle composes no children, so
the emitted statement never appears in it; the size gate passes against
the unchanged byte-identity baseline, and BENCHMARK.md numbers stand.
The new gate costs one browser test: after a Pulse click and a parent
dispose, `nestDispose.children[0].instrumentation()` returns the same
ten-slot snapshot before and after a synthetic click on the detached
child button — reachability plus frozen counters in one assertion.

### Follow-up issue or commit

`feat(component): reach child instrumentation through the parent
disposer (ADR-0066)` — the backend emission, the artifacts pin, the
browser gate, the ADR, the DECISIONS.md row, and this record.
ADR-0039's future-work sentence is discharged; the invariant list
shrinks by one. Open: transitivity is untested until a lab nests two
levels (ADR-0066 OQ1), and aggregation stays in the consumer if one
ever exists (OQ2). The other invariants hold: the key set stays sealed
at Enter/Escape; the guard literal stays `""`; the count-label literal
stays one; row guards stay single-field remove-or-commit; row scope
still has no `s!`; branch cells stay single-level two-branch with
exact click/dblclick agreement.

## Transitive child composition — the two-level round (ADR-0067)

### Scenario exercised

ADR-0066 OQ1 asked whether the `children` republication actually
composes when a child module composes its own child. The survey walked
every stage of the `<Child/>` pipeline looking for a root-only
assumption — the elaborator's capitalized-head collection and
`{Name}_spec` resolution, the ADR-0042 `propNames` check, the
LRX-VIEW-023/024 validations, the LRX-BE-030 root guard, the aliased
`import { mount as $lrx_child_0 }` emission, and the
`dom.childOffs`-gated ADR-0066 line — and found none: nothing in the
path knows whether the module being emitted is a root or somebody's
child. So the round executed rather than sealed: NestLab gained a
`Tick` leaf (state, one event, one immutable prop) composed by
`Pulse`, making `Pulse.mjs` an intermediate module that both exports
`mount` and mounts a child, and ADR-0067 records that transitivity
needs no new vocabulary — per-level republication *is* the contract,
and `children[0].children[0]` is the composed surface.

### What was pleasant

The intermediate module fell out of the existing backend untouched:
`Pulse.mjs` grew exactly the pinned child-composing shape — aliased
import, mid-mount `$lrx_child_0(node_0, ["Tick child"])`, the offset
in its `makeDisposer` list, and `disposer["children"] = [child_off_0]`
— while `NestLab.mjs` stayed byte-identical, which is the freeze
argument in one diff. The ADR-0066 design choice that the array
element *is* the mount return paid off immediately: the grandchild
gate needed no new accessor, just two index hops.

### Friction encountered

Declaration order is the one authoring constraint: `Tick`'s `_spec`
must elaborate before `Pulse` references it, which in a single file
just means the leaf is written first. Moving NestLab down the file
shifted its graph spans, so `NestLab.mjs.manifest.json` changed by
`graphHash` alone with byte-identical generated JS — a reminder that
the graph hash covers source spans, not just structure.

### Bugs found

None. The two-level path worked on the first generation, which is
itself the round's finding: the ADR-0039/0042/0066 conventions were
already component-generic, and only a witness was missing.

### Performance observations

Frozen by construction: the benchmark bundle composes no children, so
every module outside the nest bundle is byte-identical and the size
gate baseline stands. The new browser gate costs one test: a Tick
click puts exactly one `transaction:commit` in the grandchild's trace
and zero in the intermediate child's (state arrays stay separate
across levels), and after the root disposes, the detached tick button
click changes nothing — the ten-slot snapshot is frozen behind a
still-reachable two-hop path.

### Follow-up issue or commit

`feat(examples): pin transitive child composition through the
two-level NestLab (ADR-0067)` — the Tick component, the build
registration, the artifacts pins (including the leaf's no-nesting
pin), the transitivity browser gate, the ADR, the DECISIONS.md row,
and this record. ADR-0066 OQ1 is discharged. Open: prop forwarding
across levels stays ADR-0039's later phase, and tree aggregation
stays with the consumer (ADR-0066 OQ2). The other invariants hold:
the key set stays sealed at Enter/Escape; the guard literal stays
`""`; the count-label literal stays one; row guards stay single-field
remove-or-commit; row scope still has no `s!`; branch cells stay
single-level two-branch with exact click/dblclick agreement.

## Parent prop forwarding — the ChildProp round (ADR-0068)

### Scenario exercised

Close ADR-0067 OQ1 by execution: let a parent pass its own immutable
prop into a child's prop as a mount-time constant. `Pulse` now writes
`<Tick label={title}/>` instead of a fresh literal, so the NestLab
witness threads one root-supplied constant two levels down: `NestLab`
passes `title="Pulse child"` to `Pulse`, `Pulse` forwards it as the
grandchild's `label`, and `#tick-label` renders the root's literal.
The generated `Pulse.mjs` mounts the grandchild with
`$lrx_child_0(node_0, [props[0]])` — the parent's own positional
mount argument riding the nested mount call.

### What was pleasant

The survey (the round's first half) found every stage one small
extension away, because the ADR-0042 machinery already did the hard
parts positionally: `rewritePropRefs` already resolved declared prop
identifiers to indices for text children, the backend already read
`props[field]` for prop texts and already threaded the props
identifier through `mountChildren`, and `JsAst` already had
`Expr.index`. The one representational decision — `View.child`'s
`List (String × String)` cannot carry an identifier reference — had
an obvious sum-type answer (`ChildProp.lit`/`ChildProp.forward`), and
Lean's positional-pattern convention meant the arity-preserving type
change rippled into exactly the consumers the compiler listed.

### Friction encountered

Two rewrite-ordering seams needed care. `collectComponentHeads` runs
on the pre-rewrite syntax while jsx% lowering sees the post-rewrite
tree, so the child-element predicate must accept both the surface
`name={ident}` form and the internal `propRef%` form — otherwise the
child table and the lowering disagree and the backend imports a ghost
module or misses a real one. And the attr rewrite must be scoped to
capitalized child-shaped heads: a bare `ident={ident}` rewrite would
let a parent prop named like a schema field claim a controlled
input's `value={field}` binding. Also two escapes bit once each:
Lean's interpolation escapes `{` as `\{` (not `{{`), and the new
inductive's generated `injEq` lemmas had to be registered in the
axiom-manifest audit before the build went green.

### Bugs found

None in the pipeline. The `(str <|> num)*` elaborator-header
alternative and the mixed `TSyntax [`str, `num]` splice both worked
on the first compile, which was the round's parser-combinator gamble.

### Performance observations

Frozen by construction: the benchmark bundle composes no children and
forwards nothing, so every module outside the nest bundle is
byte-identical and the size-gate baseline stands. Inside the bundle
the delta is one call-site shape (`["Tick child"]` → `[props[0]]`)
plus the graph-span shifts of the edited example. The browser gate
costs nothing new — the existing document-order test now asserts the
forwarded literal.

### Follow-up issue or commit

`feat(component): forward a parent's immutable prop into a child prop
(ADR-0068)` — the `ChildProp` sum, the propRef% rewrite and
`(str <|> num)*` elaborator, the `props[i]` emission, `LRX-VIEW-044`
and `LRX-ELAB-130` with their fixtures, the NestLab witness update,
the guide section with the compiled `PropForwardMini` snippet, the
ADR, the DECISIONS.md row, and this record. ADR-0067 OQ1 is
discharged; the remaining boundary is reactivity (signals do not
cross mounts — that would need a new contract, not a `ChildProp`
relaxation) and three-level re-forwarding has no pinned witness. The
other invariants hold: the key set stays sealed at Enter/Escape; the
guard literal stays `""`; the count-label literal stays one; row
guards stay single-field remove-or-commit; row scope still has no
`s!`; branch cells stay single-level two-branch with exact
click/dblclick agreement.

## Transitive prop re-forwarding — the three-level round (ADR-0069)

### Scenario exercised

Closing ADR-0068 OQ2: does a prop forwarded *into* a component
forward *out* of it again, or does the chain break at the second
link? The round extended the NestLab chain by one level — a new leaf
`Blip` (one `note` prop, one state, one event, declared before `Tick`
per the leaf-first elaboration order) composed by `Tick` as
`<Blip note={label}/>`, where `label` is the prop `Tick` itself
receives from `Pulse` by forwarding, which `Pulse` in turn receives
from `NestLab` as the literal `"Pulse child"`. The gates pin the
generated call shape (`$lrx_child_0(node_0, [props[0]])` in
`Tick.mjs`, byte-identical to `Pulse.mjs`'s first-level forward), the
three-level literal flow (`#blip-note` reads the root-supplied
string), and `children[0].children[0].children[0]` reachability with
the dispose-freeze contract.

### What was pleasant

The survey took one function read. `rewriteForwardAttr` resolves the
attr value against `props.idxOf?` on the component's declared prop
inventory and nothing else — there is no code path that could
distinguish a literal-fed prop from a forward-fed one, so
transitivity was true by construction and the round was witness-only:
zero compiler lines changed, and `lake build` went green on the first
try after the one whitelist correction below. The manifest diff was
itself a re-witness: `Tick.mjs.manifest` gained exactly the
`child-components` feature and `./Blip.mjs` import that `Pulse`'s
gained at ADR-0067, confirming "module that composes a child" is one
shape regardless of chain position.

### Friction encountered

The closed element whitelist: the leaf's heading was first written
`<h4>`, which `LRX-VIEW-007` rejects (the whitelist stops at `h3`).
Extending `HtmlTag` for a witness would have been vocabulary creep in
a round whose decision is "no new vocabulary", so the leaf uses
`<span id="blip-note">`. Every touched gate was mechanical: the elab
pin for `Tick` flips from leaf-shape to composer-shape, the leaf
no-nesting pin moves to `Blip`, the browser spec adds the
great-grandchild reachability test as a one-level-deeper copy of the
ADR-0067 test, and `check_component_codegen.sh` gains one
`node --check`.

### Bugs found

None. Fourteen browser tests green including the new three-level
gate; the leaf's transaction commits in its own state array and the
re-forwarding intermediate's trace stays commit-free, so state
isolation composes with the chain.

### Performance observations

Frozen by construction: the benchmark bundle composes no children, so
every module outside the nest bundle is byte-identical and the
size-gate baseline stands. Inside the bundle the delta is one new
leaf module plus the graph-span shifts of the edited example.

### Follow-up issue or commit

`feat(examples): pin transitive prop re-forwarding through the
three-level NestLab (ADR-0069)` — the `Blip` leaf, the `Tick`
re-forward, the build entry, the elab/artifact/browser gates, the
ADR, the DECISIONS.md row, and this record. ADR-0068 OQ2 is
discharged; depth is now argued inductively (every link is locally
the witnessed ADR-0068 shape), so no deeper lab is warranted. The
remaining prop boundary is reactivity alone, and fan-out
re-forwarding (two forwards from one receiving component) is the one
unwitnessed composition. The other invariants hold: the key set stays
sealed at Enter/Escape; the guard literal stays `""`; the count-label
literal stays one; row guards stay single-field remove-or-commit; row
scope still has no `s!`; branch cells stay single-level two-branch
with exact click/dblclick agreement.

## Fan-out prop re-forwarding — the sibling-leaf round (ADR-0070)

### Scenario exercised

Closing ADR-0069 OQ2: does one receiving component forward the same
received prop into two children, or does something in the pipeline
assume one child per composer? The gap was doubled — multi-static-
child composition itself was unwitnessed (every composer in the tree
had exactly one child), so the round pinned fan-out composition and
fan-out re-forwarding with one witness: a second leaf `Chip` (one
`tag` prop, one state, one event, declared next to `Blip`) composed
by `Tick` as `<Blip note={label}/>, <Chip tag={label}/>`. The gates
pin the scaled shapes: child table `["Blip", "Chip"]`, two aliased
imports and two `[props[0]]` calls in `Tick.mjs`,
`disposer["children"] = [child_off_0, child_off_1]`, both leaves
rendering the root-supplied literal three levels down, and
`children[0].children[0].children[1]` reachability with the
dispose-freeze and sibling-independence contracts.

### What was pleasant

The survey was three reads with one answer each: the elaborator
collects child heads in first-occurrence order into an array, the
backend allocates imports and `child_off_{n}` per entry from that
array, and the ADR-0066 republication emits the whole `childOffs`
list. Nothing anywhere assumes length one, so the round was again
witness-only — zero compiler lines, and every gate went green on the
first build. Each `View.child` reference carries its own `ChildProp`
list, so the two `.forward 0` entries were independent by
construction and the "same received prop, twice" case needed no
special pleading.

### Friction encountered

None new. The `h4` whitelist lesson from ADR-0069 was applied
preemptively (`Chip` renders `<span id="chip-tag">`), and the
five-way `match` in `NestLabBuild` is at the edge of pattern-match
legibility — a sixth module would want a list-driven emit loop. The
one non-obvious gate edit was retroactive: the ADR-0069 three-level
reachability test pinned `tick.children.length` to 1, which the
fan-out flips to 2 — a reminder that reachability pins encode the
whole sibling row, not just the indexed child.

### Bugs found

None. Fifteen browser tests green including the new fan-out gate; the
sibling leaf's transaction commits in its own state array while both
the first leaf and the re-forwarding parent stay commit-free, so
state isolation holds across the fan-out width as well as the chain
depth.

### Performance observations

Frozen by construction: the benchmark bundle composes no children, so
every module outside the nest bundle is byte-identical and the
size-gate baseline stands. Inside the bundle the delta is one new
leaf module plus the graph-span shifts of the edited example.

### Follow-up issue or commit

`feat(examples): pin fan-out prop re-forwarding through the Chip
sibling leaf (ADR-0070)` — the `Chip` leaf, the `Tick` fan-out, the
build entry, the elab/artifact/browser gates, the ADR, the
DECISIONS.md row, and this record. ADR-0069 OQ2 is discharged; width
now composes with depth (n children are n independent table entries),
so arbitrary static trees of constant forwards are covered and no
wider lab is warranted. The remaining prop boundary is reactivity
alone, and the one unwitnessed composition shape is repeated
composition of the *same* child (two references to one deduplicated
table entry). The other invariants hold: the key set stays sealed at
Enter/Escape; the guard literal stays `""`; the count-label literal
stays one; row guards stay single-field remove-or-commit; row scope
still has no `s!`; branch cells stay single-level two-branch with
exact click/dblclick agreement.

## Repeated child composition — the second-instance round (ADR-0071)

### Scenario exercised

Closed ADR-0070 OQ2: one parent composing the same child module
twice. `Tick` gained a second `Chip` reference with a deliberately
different prop shape — `<Chip tag={label}/>, <Chip tag="fixed
chip"/>` — so one witness pins both halves of the dedup split: the
child table (and the aliased import, and the manifest specifier)
dedups by name, while every reference keeps its own `ChildProp` list
and its own `child_off_{n}`. The survey confirmed the split by
construction — `childNames.contains` guards only the table entry,
`mountChildren` resolves every reference through `childMounts.find?`
and allocates offsets by `childOffs.length` — so the round is
witness-only: the elab pin fixes the three-reference shape with mixed
forward/literal props, the artifact gate pins one `./Chip.mjs` import
(`$lrx_child_2` pinned absent) called twice with `[props[0]]` and
`["fixed chip"]`, and the browser gate pins the two instances
rendering different texts, `children[2]` reachability, per-instance
commit counts (1 vs 2), and the root-disposal freeze across all
three leaves.

### What was pleasant

Nothing in the pipeline had a length-one or one-to-one assumption to
unwind — the same declaration-order collection that scaled fan-out
scaled multiplicity, and the generated `Tick.mjs` came out exactly as
predicted on the first build: two imports, three calls, three
disposer entries. The mixed forward/literal witness cost nothing
extra: each reference's prop array is emitted independently, so the
independence pin is just two adjacent generated lines.

### Friction encountered

The anticipated hazard was real: the `Chip` template carried static
ids, which two instances would duplicate — axe would flag
`duplicate-id` and every `#chip-*` selector would silently resolve to
the first instance. Switching the leaf template to classes
(`.chip-tag`/`.chip-text`) and the spec selectors to list-form
`toHaveText` assertions was mechanical, but it is a template-author
lesson worth stating: a component meant for composition should not
mint static ids. Playwright's strict mode also forced the button
locators through `.first()`/`.nth(1)` once two "Chip" buttons
existed — the strictness caught exactly the ambiguity the id switch
was about.

### Bugs found

None. Fifteen browser tests green with the widened gate; the
repeated instance commits in its own state array while the forwarded
instance, the first leaf, and the re-forwarding parent all stay at
their own counts, so instance identity is positional, not nominal.

### Performance observations

Frozen by construction: the benchmark bundle composes no children, so
every module outside the nest bundle is byte-identical and the
size-gate baseline stands. Inside the bundle no module was added and
no manifest changed — the delta is three generated lines in
`Tick.mjs` plus the graph-span shifts of the edited example.

### Follow-up issue or commit

`feat(examples): pin repeated child composition through the second
Chip instance (ADR-0071)` — the second `Tick` reference, the
class-for-id template switch, the elab/artifact/browser gates, the
ADR, the DECISIONS.md row, and this record. ADR-0070 OQ2 is
discharged; static-child composition is now covered in depth
(ADR-0069), width (ADR-0070), and multiplicity (ADR-0071), so no
further static-composition lab is warranted. The remaining prop
boundary is reactivity alone (carried since ADR-0068 OQ1). The other
invariants hold: the key set stays sealed at Enter/Escape; the guard
literal stays `""`; the count-label literal stays one; row guards
stay single-field remove-or-commit; row scope still has no `s!`;
branch cells stay single-level two-branch with exact click/dblclick
agreement.

## Child composition in region rows — the boundary-sealing round (ADR-0072)

### Scenario exercised

The last place a `<Child/>` head could appear without a contract:
inside a sealed keyed-region row template. The survey put
`<Chip tag="x"/>` into a NestLab-shaped region row and watched where
it died. Not in the backend — `collectComponentHeads` only walks view
items, but `lowerRowElement` also never lowers a capitalized head to
`View.child`, so the `childMounts.find?` miss (`LRX-BE-029`) is
unreachable. It died at elaboration in `leanrx_jsx_tag%` with the
generic `LRX-VIEW-007: unsupported element <Chip>` — early, but
misleading: the tag-whitelist message (the `<h4>` answer) for what is
actually a lifecycle-contract conflict. The round sealed the boundary
with a dedicated diagnostic: `checkRowElementHead` fires
`LRX-ELAB-131: a sealed row template does not compose child
components; mount <Chip/> from the component view instead` at the
head's own span, before attr lowering so prop-shaped attrs never
produce a stray unknown-attribute error first.

### What was pleasant

The check is one guard called from both `lowerRowElement` arms, and
nested heads come free because `lowerRowChild` delegates every
element child back to `lowerRowElement`. The witness
(`ChildInRegionRow.lean`) keeps a checked `Chip` spec in scope, so it
also pins that the rejection is about the row contract, not a missing
`_spec` — one fixture separates `LRX-ELAB-131` from `LRX-ELAB-130`
and `LRX-VIEW-007` at once.

### Friction encountered

The first repro drafted a one-field region and discovered that
`append roster (expr,)` is not a parse — single-field appends take
`(expr)` without the trailing comma; the repro moved to the two-field
NestLab shape rather than relitigating tuple syntax. Otherwise the
round was as small as a round gets: the survey's two candidate death
sites (late backend vs. sealed syntax) were both wrong in the same
informative way — the whitelist caught it first.

### Bugs found

None in the pipeline — the boundary was already closed, just
mislabeled. The finding is diagnostic-quality: "unsupported element"
invites a tag-whitelist request; the new message names the actual
contract and points at the supported path.

### Performance observations

Frozen trivially: the change is elaborator-only (one throw before
any term is built), so no generated module, manifest, or host byte
moved; byte identity and the size gate stand without re-measurement.

### Follow-up issue or commit

`feat(elab): reject child composition in sealed row templates with
LRX-ELAB-131 (ADR-0072)` — the `checkRowElementHead` guard, the
compile-fail witness and its registration, the language-guide
sentence, the ADR, the DECISIONS.md row, and this record. The
static-composition surface is now closed on all sides: supported and
witnessed in views (depth ADR-0069 × width ADR-0070 × multiplicity
ADR-0071), rejected with a dedicated diagnostic in rows (ADR-0072).
Per-row composition stays an OQ pending a per-row disposer
republication contract with a concrete consumer. The remaining prop
boundary is reactivity alone (ADR-0068 OQ1). The other invariants
hold: the key set stays sealed at Enter/Escape; the guard literal
stays `""`; the count-label literal stays one; row guards stay
single-field remove-or-commit; row scope still has no `s!`; branch
cells stay single-level two-branch with exact click/dblclick
agreement.

## Misshapen child references — the fallback-guard round (ADR-0073)

### Scenario exercised

What a user sees when a capitalized head with a checked `_spec` in
scope leaves the child-reference contract in a component view. Three
NestLab-derived reproductions: `<Chip tag="x"> ["extra"]` (children
on the reference), `<Chip tag={heading ++ "!"}/>` (composed dynamic
value), `<Chip onClick={notAnEvent}/>` (unclaimed non-prop
attribute). All three fell through `typedElement` into the
`componentCall` typed-application fallback — the path that exists for
spec-less template functions (ADR-0039) — and died identically with
`Unknown identifier 'Chip'` plus the `sorryAx` cascade: the compiler
denying the existence of the component the user is looking at. The
survey also pinned two neighbors that never reach the fallback:
`<Chip onClick={declaredEvent}/>` is claimed by the RHS sugar's
string rewrite first and reports `LRX-ELAB-112` (which names the
declared prop inventory), and spec-less forwarding stays
`LRX-ELAB-130`.

### What was pleasant

The constraint that killed candidate (b) — the macro cannot see
`_spec`, and the misuse shape `name={term}` is byte-identical to the
legitimate `<Metric value={metricValue}/>` spec-less application — is
exactly the split the fix rides: the *reason* is chosen at macro time
where the shape is visible, the *spec check* runs at term-elab time
where the spec is visible. `leanrx_jsx_component_fallback%` wraps the
same application term the macro used to emit, so the no-spec path
elaborates the identical syntax and ADR-0039 needs no migration —
the existing `ViewSurface` test is the non-regression witness.

### Friction encountered

The first witness draft used `<Chip onClick={poke}/>` with `poke` a
declared host event — and got `LRX-ELAB-112`, not the new
diagnostic, because the RHS sugar rewrites declared event references
to strings before `literalPropPairs` looks. The fallback only sees
values the sugar and the forwarding rewrite both declined. The
witness pair therefore pins the two arms that genuinely reach it:
non-empty children, and a composed value against a declared parent
prop (the exact ADR-0068 boundary).

### Bugs found

One diagnostic-quality hole, closed: the fallback now reports
`LRX-ELAB-132` with the contract (props are literals or one
forwarded parent prop; children live in the child's own view)
instead of an unresolved identifier. One latent oddity recorded, not
changed: a *spec-less* head with children silently drops them —
pre-existing `componentCall` behavior, no live surface writes it
(ADR-0073 OQ1).

### Performance observations

Frozen trivially: the guard is error-path-only term elaboration; the
success path emits the same syntax as before, so no generated
module, manifest, or host byte moved — byte identity and the size
gate stand without re-measurement.

### Follow-up issue or commit

`feat(elab): reject misshapen child references at the
typed-application fallback with LRX-ELAB-132 (ADR-0073)` — the
`leanrx_jsx_component_fallback%` guard, the two compile-fail
witnesses and their registration, the language-guide paragraph, the
ADR, the DECISIONS.md row, and this record. The spec'd-head misuse
boundary is now fully labeled: LRX-ELAB-112 (wrong names/order),
LRX-ELAB-130 (forwarding without a spec), LRX-ELAB-131 (row
templates), LRX-ELAB-132 (shape outside the child-reference
contract). Remaining OQs: silent child-drop on spec-less heads
(OQ1), the logical view's raw fallback (OQ2), per-row composition
(ADR-0072 OQ1), and reactive child props (ADR-0068 OQ1).

## Silent child drop on spec-less heads — the closing round (ADR-0074)

### Scenario exercised

What a user sees when a *spec-less* capitalized head carries
children. On a `ViewSurface`-derived copy of the live ADR-0039
surface: `<Metric value={metricValue}> ["extra"]` compiled clean,
`spec.check` passed, `Backend.Component.emit` succeeded, and the
printed module contained no `"extra"` — no error, no render, the
child simply gone (ADR-0073 OQ1 confirmed end to end). The logical
reference view shared the drop byte for byte:
`<LogicalMetric label="m"> ["extra"]` lowered to
`element "main" [] [element "p" … [text "m"]]`. And the logical
view's spec'd head still denied the component's existence —
`<Chip tag="x"/>` under `Region.LogicalNode` reported the bare
`Unknown identifier 'Chip'` (OQ2 reconfirmed).

### What was pleasant

The ADR-0039 contract question answered itself once stated
precisely: the sealed "ordinary meaning" is the application of the
head to its rewritten *attributes* — children never reached
`componentCall`, so no observable program can depend on writing
them, and rejecting the shape converts dead syntax into a
diagnostic without moving the sealed surface. The `childCount`
numeral rides the exact macro-time/term-elab-time split ADR-0073
built: the count is visible at the macro, the spec at the
elaborator, and the fall-through still emits the identical
application term. Wrapping `logicalElement` in the same guard was
one call site — the symmetric OQ2 fix cost a reason string.

### Friction encountered

Inspecting the emitted module from a scratch `#eval` took three
tries: `Emitted` exposes `module`/`manifest` (no `contents`), the
printer lives at `Js.Printer.module` (not `Backend.Js.Printer`),
and interpolating a `Prop`-valued comparison needs `decide`. The
logical pin also caught `LogicalNode.element` taking a plain
`String` tag while the elaborator writes `HtmlTag.name` — fine for
the macro, but a hand-written reference node uses the bare string.

### Bugs found

One silent-drop hole, closed in both views: non-empty children on a
spec-less capitalized head now report `LRX-ELAB-133` (the head "is
an ordinary application (ADR-0039) and consumes no children")
instead of vanishing; a spec'd head in the logical view now reports
`LRX-ELAB-132` with "checked components nest in the typed component
view only" instead of the unresolved identifier. No silent-drop
path remains on the capitalized-head surface.

### Performance observations

Frozen trivially again: error-path-only elaboration. The spec-less
no-children fall-through emits the same syntax as before — pinned
typed by the existing `<Metric value={metricValue}/>` test and
logical by the new `logicalDashboard` pin — so no generated module,
manifest, or host byte moved; byte identity and the size gate stand
without re-measurement.

### Follow-up issue or commit

`feat(elab): reject children on spec-less capitalized heads with
LRX-ELAB-133 and guard the logical fallback (ADR-0074)` — the
`childCount` numeral on `leanrx_jsx_component_fallback%`, the
`logicalElement` wrapper, three compile-fail witnesses
(TemplateCallWithChildren, ChildRefInLogicalView,
TemplateChildrenInLogicalView) and their registration, the
`logicalDashboard` pass-through pin, the language-guide paragraph,
the ADR, the DECISIONS.md row, and this record. ADR-0073 OQ1 and
OQ2 are closed; the capitalized-head misuse map is complete in both
views (112/130/131/132/133). Remaining OQs: per-row composition
(ADR-0072 OQ1) and reactive child props (ADR-0068 OQ1).

## Per-row child composition — the ADR-0072 OQ1 round (ADR-0075)

### What was attempted

Close ADR-0072's open question by survey-then-execution: either
seal per-row `<Child/>` composition inside keyed-region row
templates on a minimal surface, or fix the conflict axes as
rejection witnesses. The survey found every lifecycle hook already
present — all removal paths (reconcile, `removeAt`, region dispose)
funnel through the generated dispose callback, which was a no-op
placeholder; the component backend never emits `swapAt`/`removeAt`
itself; a child mount appends exactly one root, preserving the
structural `childAt` and cell-action index math — so the round
executed: `RowNode.child` with `RowChildProp.lit/field`, the row
mount callback mounting `$lrx_child_k(cell, [item[i+1]])`, the
`$lrxRowChild` stash on the row root, the dispose-callback splice
and invoke, the live `childInventory` shared between the region
record's last slot, the `update`/`updateAt` context argument, and
`disposer["children"]`. NestLab grew the unwritten `origin` field
and a per-row `<Chip tag={origin}/>` — four Chip instances through
one aliased import.

### What was pleasant

The host needed nothing: `createKeyedRegion` already forwarded a
context argument to every callback and generated code had always
passed `null`, so the live inventory rode a slot that existed since
ADR-0041 — ABI stays 17. The immutable-prop boundary translated
mechanically: "props are mount-time constants" becomes "row child
props are row-mount constants", and the writer set (row event
stages, key-branch arms, broadcasts) is fully static, so
`LRX-VIEW-045` makes divergence unrepresentable instead of
documenting it. Delegated events needed no carve-out — a click
inside the row chip resolves the chip's own cell, whose action
entry is `""`.

### Friction encountered

The region's full dispose calls `disposeItem(handle, key)` without
context, so the inventory splice had to be guarded (`if (context)`)
— acceptable because post-dispose the static ADR-0066 array also
keeps its disposed entries. Message strings in `throwErrorAt`
interpolate `{…}`, so the diagnostic's `name={field}` needed the
`\{` escape. The environment audit fails closed on every new
mutual walker and evaluated predicate: four `_unsafe_rec` entries,
one `unsafe_1` helper, and three `injEq`/`propext` pairs joined the
reviewed lists. The child table order follows first occurrence, so
the region item (declared before the view) makes Chip
`$lrx_child_0` and Pulse `$lrx_child_1` in NestLab.

### Bugs found

None in existing behavior — the sealed surface is new. The
boundary is witnessed per axis: children on the head and composed
prop values keep `LRX-ELAB-131` (ChildInRegionRow repointed,
RowChildComposedProp), multiplicity and branch placement and the
written-field conflict land on `LRX-VIEW-045` (RowChildTwoPerRow,
RowChildInBranch, RowChildWrittenField), and an id-carrying child
template lands on `LRX-ELAB-135` (RowChildStaticId).

### Performance observations

All codegen changes are gated on a region actually composing a
child: modules without one emit byte-identical code (Pulse/Tick/
Blip/Chip byte-diffed clean; the benchmark bundle never enters the
path), so the size gate and BENCHMARK.md stand without
re-measurement. Per-row cost is one child mount call, one property
stash, and one inventory push per row mount; one splice-by-identity
and one dispose call per row removal.

### Follow-up issue or commit

`feat(region): seal per-row child composition through the row
dispose callback (ADR-0075)` — `RowNode.child`/`RowChildProp`, the
row lowering behind `componentHead?`, the written-field and
placement checks (`LRX-VIEW-045`), the static-id evaluated
predicate (`LRX-ELAB-135`), the live `childInventory` and region
record slot, the NestLab origin field and row chip, six compile-fail
witnesses and registrations, the derived artifact gate, three
browser specs, the language-guide paragraph, the ADR, the
DECISIONS.md row, and this record. ADR-0072 OQ1 is closed; the
remaining prop-boundary OQ is ADR-0068 OQ1 (reactive props), still
rejected.

## Row children × region features — the coexistence round (ADR-0076)

### What was attempted

Gate ADR-0075's live `childInventory` slot against the region
features it had only been shipped apart from — ADR-0050 counts,
the ADR-0051 filter, ADR-0063 persistence — or seal whichever axis
interfered. The survey found all four suspected axes coherent:
the record construction appends slots in exactly the
`regionChildSlot` order (base five, counts?2, filter?1, inventory),
hydration rides the shared commit sweep whose reconcile forwards
the inventory slot as the child context, the filter's
`childAt(container, i)` navigation only ever sees row roots because
the child mounts *inside* the row root, and every count/visibility/
persistence subject reads the row table, never the DOM or the
inventory. So the round was pure execution: Mix Lab
(`examples/MixLab.lean`) puts all four features plus a static and a
per-row `<Badge/>` on one `crew` region, the derived artifact gate
pins the widest 9-slot record literal and the `regions[0][8]`
child context at both sweep call sites, and six browser tests pin
hydration-mounted badges, filter-hidden badge survival, and
removal decrementing counts and inventory in one commit.

### What was pleasant

Zero code changes — backend, elaborator, and hosts untouched, ABI
17 stands. The lab compiled on the first `lake build` and all six
browser tests passed on the first run: the slot formula, the
context forwarding, and the sweep ordering were already right,
they were just ungated. The commit sweep's ordering (counts →
hidden → reconcile → filter → persist, all reading one `touched`
flag captured before the reconcile consumes the dirty bit) meant
"removal syncs counts and inventory" needed no reasoning beyond
"same transaction".

### Friction encountered

One tooling false positive: the placeholder scanner is line-based
and flagged the Mix Lab doc comment when a wrapped sentence put
the word "constant" at a line start — reworded to
"prop-stability", no policy change. Otherwise none structural. The
survey's one real finding is a gap, not a
bug: the filter slot is spelled inline (`5 + counts?2`) at its own
call site rather than through a shared helper with
`regionChildSlot` — coherent today, and now held by the pinned
record literal either way.

### Bugs found

None. The combination behaves as composed: hidden rows keep their
badges mounted and stateful (row-identity invariant), hydrated
rows are full citizens of the child vocabulary, and badge
transactions are invisible to counts, metrics, and storage.

### Performance observations

No generated-code change anywhere outside the new lab: NestLab,
ToggleLab, and the benchmark bundle are byte-identical, so the
size gate and BENCHMARK.md stand without re-measurement. Mix Lab's
sweep costs are the sum of its parts — no combination-specific
overhead exists in the emitted code.

### Follow-up issue or commit

`feat(examples): gate row-child composition against counts, filter,
and persistence in Mix Lab (ADR-0076)` — the Mix Lab example and
build/main executables, lakefile and check-script wiring, the
derived artifact gate pinning the widest record layout, six
browser tests, the ADR, and this record. Open: a broadcast ×
row-children gate (retained-row re-render must leave the inventory
untouched) and the two-child-regions inventory interleaving,
both waiting on a consumer lab.

## Broadcasts and a second child region — the ADR-0076 OQ closure round (ADR-0077)

### What was built

The round that closes ADR-0076's two open questions as gates. The
survey came first and found both axes coherent by construction:
`createKeyedRegion.update` mounts only entries whose key was not
retained, and a broadcast retains every key (it rewrites tuples,
never keys), so the reconcile it raises re-renders retained rows
through the update callback alone — and `rowUpdateTargets` yields
nothing for a `.child` cell, so that callback cannot even reach a
row child. On the second axis, the record construction emits one
`const childInventory` and hands the same identifier to every
child-composing region's record at its own `regionChildSlot`
position, and each dispose callback splices by `indexOf` of its
own row's stashed closure instance. So again pure execution: Mix
Lab gains a `markAllDone` broadcast (`update crew (set done
"true")` — `done` written, `tag` still never written) and a
`pins` region composing `<Badge tag={note}/>` with no other
features — the bare 6-slot record next to crew's widest 9-slot
one, and the first two-region component in the repository. The
artifact gate pins the two-record literal sharing one inventory
identifier (slot 5 next to slot 8), the broadcast body, both
dispose splices, and the pins no-op update callback; three new
browser tests pin badge identity across a broadcast, the
chronological cross-region interleaving of the inventory, and
splice isolation in both removal directions. A new compile-fail
witness (`RowChildBroadcastField`, LRX-VIEW-045) makes the
rejection's broadcast-writer arm explicit.

### What was pleasant

Zero code changes again — ABI stays 17, and the first multi-region
component ever compiled worked end to end on the first generation:
per-region dispatch tables, delegated listeners, dispose functions,
and commit-sweep entries all index cleanly by region position. The
interleaving spec needed no new instrumentation: driving each
badge's commit count to its inventory position identified every
entry through the existing `children` array.

### Friction encountered

None structural. One self-inflicted spec bug: a page-scoped
`globalThis` capture compared from Node — caught on
reread before the first run, the paired-capture idiom from the
existing tests was the fix.

### Bugs found

None. Retained rows keep their badge instances, hit counts, and
inventory positions across a broadcast (metrics: mounts and
disposals frozen, updates +N); the shared inventory is
chronological across regions behind the static seed; a removal in
either region splices exactly its own entry and leaves the other
region's metrics untouched.

### Performance observations

No generated-code change outside Mix Lab itself: the benchmark
bundle, NestLab, and every other lab are byte-identical, so the
size gate and BENCHMARK.md stand without re-measurement. The pins
region's retained-row callback is the no-op — a second
child-composing region costs exactly its own mounts.

### Follow-up issue or commit

`feat(examples): gate broadcasts and a second child-composing
region on the shared inventory (ADR-0077)` — the Mix Lab
extension, the two-record artifact gate, three browser tests, the
broadcast-writer witness, the ADR, and this record. Open: nothing
mechanism-shaped — three-plus regions add no new machinery, and
the interleaving/isolation specs extend directly if a lab ever
declares one.

## Two regions, four features — the distribution round (ADR-0078)

### What was built

The generalization round Mix Lab's second region opened. ADR-0077
made the repository's first two-region component, but every region
feature was still carried by exactly one of the two: `crew` had
counts, a filter, and persistence; `pins` had none. The survey
asked what happens when a feature sits on *both* regions, and
checked five places in the backend before touching anything —
every emitted temporary already carries the region index
(`filter_scan_{i}`, `count_next_{i}_{slot}`, `persist_rows_{i}`);
the filter container slot and the child inventory slot are both
computed *inside* the per-region loop from that region's own
feature set; `countRefs`/`countCache` are per-record arrays sized
by the cells naming that region; region-subject selections keep
their global document-order labels while re-evaluating under their
own region's touched flag; and `Update.sequence` composes region
actions across regions freely, each raising its own dirty flag.

All five coherent — but the survey found one axis that was not
merely ungated: `validatePersists` capped the whole component at
one persist item, even for two regions under two different keys,
while the backend was already index-generalized
(`hydrateFunction … persistIndex`, a mount loop over
`persists.zipIdx`, a write-back inside the per-region sweep). The
cap was stage-1 scaffolding. So this round has a code change after
all: the cap becomes one persist item *per region* with keys
distinct across the component — the real invariant is one writer
per key, and both violations (a region persisting twice, two
regions sharing a key) stay `LRX-TYPE-118` because both would make
one commit sweep emit two write-backs racing for one slot.

Mix Lab's `pins` then took its own count cell, its own emptiness
selection, its own persist key, and the component took one chained
cross-region event (`append pins (…) then remove crew (…) then
set added (…)`). The artifact gate pins the two-record literal
with crew's container at slot 7 and pins' *inventory* at slot 7 —
the same number meaning two different things in two records, which
is the sharpest evidence available that feature slots are computed
per region.

### Friction encountered

None structural. The one design tension was real and had to be
resolved by choosing: giving `pins` a filter too would have made
both records identical in width and slot numbering, erasing the
divergence that makes the layout gate sharp. Kept `pins`
unfiltered, gated the crew-filter-flip non-interference instead,
and recorded two filtered regions as an open question with its
construction argument.

### Bugs found

None. Two hydrations run in declaration order and seed the shared
inventory crew-first; a write in one region rewrites its key
alone; the chained event commits once with `region:pins:append`
before `region:crew:removeIf` (event order) and
`region:crew:update` before `region:pins:update` (sweep order);
and a crew filter flip leaves every pins row, child instance,
metric, and the pins key untouched.

### Performance observations

No generated-code change outside Mix Lab: the benchmark bundle,
NestLab, ToggleLab, and every other lab are byte-identical, so the
size gate and BENCHMARK.md stand without re-measurement. A second
persisted region costs exactly one more hydrate function and one
more write-back, both behind their own region's touched flag.

### Follow-up issue or commit

`feat(component): persist one key per region and gate the
two-region feature distribution (ADR-0078)` — the
`validatePersists` generalization, two compile-fail fixtures (a
shared key across regions, a region persisting twice), the Mix Lab
extension, the two-record artifact gate, three browser tests, the
guide update, the ADR, and this record. Open: two *filtered*
regions, and two filters driven by one state field — both coherent
by construction, neither with a consumer lab.

## Three filtered regions, two fields — the filter distribution round (ADR-0079)

### What was built

The round ADR-0078 left open. Every filtered component in the
repository carried exactly one filter, so the ADR-0051 sweep had only
ever been emitted at region index 0 — the repository-wide scan suffix
was `_0` and nothing else. The survey checked five places before
touching anything: the sweep allocates `filter_scan_{i}` /
`filter_row_{i}` inside the per-region loop; the container slot is
`5 + counts?2` computed from that region's own feature set; the wake
guard is `region_touched_{i} || changed[filterField]`, one flag and one
bit both named per region; the commit sweep walks regions in
declaration order with each region's whole block inside one iteration;
and `validateFilters` rejects a duplicate *region*, never a duplicate
field. All five coherent, and — unlike ADR-0078's persist cap — with no
scaffolding limit hiding behind them.

So the round gates the combination, and the interesting decision was
*where*. Mix Lab is the widest component in the repository and the
natural home for new combinations, but its sharpest gate is the
coincidence that crew's filter container and pins' child inventory both
land on slot 7; giving `pins` a filter would move the inventory and
erase that witness. The combination therefore went to a new lab —
Twin Lab, the first example module added since ADR-0067 — deliberately
narrow at three regions, no children, no persistence, no routing:
`left` with a count (container at slot 7 of eight), `right` and `solo`
without (container at slot 5 of six), `left` and `right` filtered by
`mode` with inverted arm tables, `solo` filtered by `tone`, and a
`stir` event appending to `solo` while writing `mode` so one commit
wakes three sweeps for two different reasons.

### Friction encountered

Two small ones. The row `remove` button had to be nested one level
deeper than it first was — `LRX-VIEW-027` requires a row event to sit
strictly inside a row cell, not directly under the row root, which is
exactly what the delegated cell-index dispatch needs. And measuring a
trace slice from a browser spec needs the mark stashed on `globalThis`
*before* the click; a Node-side variable is not in page scope.

### Bugs found

None. A `mode` flip evaluates `left` then `right` and never `solo`, in
one commit with two evaluate ticks and no mount or disposal anywhere; a
`tone` flip evaluates `solo` alone and leaves both twins' `hidden`
values and region metrics identical; a bare append or removal in `left`
wakes `left`'s sweep alone even though its twin shares the filter
field; and `stir` commits once with the append first (event order) and
all three evaluations exactly once in region declaration order, the
touched region reconciling before its own sweep while the untouched
twins never reconcile at all. The inverted tables are what make the
shared-field case unfakeable: one field value hides complementary rows
in the two regions.

### Performance observations

No generated-code change outside the new module: every other lab and
the benchmark bundle are byte-identical, so the size gate and
BENCHMARK.md stand without re-measurement. A second filtered region
costs one more scan loop behind its own guard — nothing is shared
between sweeps, and an unwoken sweep emits no trace entry at all.

### Follow-up issue or commit

`feat(examples): gate two filtered regions and a shared filter field in
Twin Lab (ADR-0079)` — the new example module and its three script
registrations, the artifact gate, six browser tests, the
`FilterRegionTwice` compile-fail witness, a compiled language-guide
snippet, the guide update, the ADR, and this record. Open: a filter
beside a pending-row drain at region index > 0, and a route over one of
two filtered fields.

## A route over a shared filter field — the ADR-0079 OQ closure round (ADR-0080)

### What was built

Both of ADR-0079's open questions, closed on Twin Lab. The route one
needed a decision first, so the round started by making the ambiguity
reproducible instead of arguing about it: two scratch components,
identical except for which literal the route arm names, one rejected
and one accepted purely because `filter left` is written above `filter
right`. `validateRoutes` was reading the routed field's filter table
with `spec.filters.find?` — the first match — which was the only
sensible reading while a component could have one filter, and stopped
being one when ADR-0079 made two legal.

Nothing downstream agreed with `find?`. The route arm functions, the
hash dispatch chain, and the mount seed are functions of the *route*
table alone; each region's filter chain is emitted from its own arms and
falls through to show-all on a literal it does not name; one
`hashchange` is an ordinary set-field transaction, so `changed[field]`
wakes every sweep guarded on that field; and `writeHash` sits in
`if (changed[route.field.index])`, once per route item, ahead of all the
sweeps. The runtime already treated the field's literal space as the
union of the tables over it. So the sealed set became the union, and the
`LRX-TYPE-117` diagnostic now names every table it was computed from
rather than whichever one came first.

Twin Lab carries both witnesses. `filter right` gained a third arm on
`"mixed"` — a literal its twin does not name — and `route mode` maps
`#/mixed` onto it, which is legal only through the union; at runtime
`"mixed"` filters `right` and leaves `left` showing every row.
`row right toggle` puts a reflected checkbox in `right`'s rows writing
the very field `right`'s filter reads, so one commit drains the retained
row through `updateAt` and re-selects it at region index 1 — the
drain-beside-filter pairing that had only ever run at index 0.

### Friction encountered

Routing a field the existing tests already flip changed what those tests
measure. Every `mode` button click now lands *two* commits: the flip,
whose commit writes the canonical hash, and the `hashchange` the write
provokes, whose dispatch is an equal-value set-field commit. Three
ADR-0079 tests asserted `commits + 1`. Papering over that with a sleep
would have been the wrong repair — the echo is a real, countable
property — so the trace windows were widened over both commits and the
assertions restated: one changed bit, two sweeps once each, one
`route:mode:write`, across two `transaction:commit`s of which only the
first does any work. The tests that merely need the echo *out of the
way* got a `flipMode` helper that polls the commit counter to `+2`
rather than waiting on a timeout.

Worth recording for the next round: a hash-*dispatched* flip is one
commit, not two, because the write its commit would make is equal-value
and fires no further `hashchange`. The echo exists only when the flip
originates outside the hash.

### Bugs found

One, and it was the round's subject: the first-match filter lookup made
a type error depend on declaration order, and pointed the diagnostic at
the wrong table while doing it. Everything else held. `#/mixed` seeds at
mount and filters `right` alone; one `hashchange` evaluates `left` then
`right` and never `solo`, with one route write for the two regions
sharing the field; the row toggle drains before its own sweep in one
commit, `left` asleep throughout, one update and no mount, move, or
disposal, with row identity and the ADR-0060 checked reflection intact.

### Performance observations

Validation-only: every generated artifact outside Twin Lab is
byte-identical, so the benchmark size gate and BENCHMARK.md stand
without re-measurement. Inside Twin Lab the route costs four arm
functions, one dispatch chain, one seed fold, and one write block — all
per *route item*, none per filtered region.

### Follow-up issue or commit

`feat(component): seal a route onto the union of its field's filter
tables (ADR-0080)` — the `validateRoutes` change and its diagnostic, the
Twin Lab route, third arm and row event, the artifact gate's union and
drain pins, three new browser tests plus four restated ones, the
`RouteLiteralOutsideFilterUnion` fixture with its two-span check, the
compiled language-guide snippet and guide text, the ADR, and this
record. Open: a persisted region under a route, and whether a row write
that provably cannot change a selection should still wake the sweep.

## One hash, one writer — the route-cap seal (ADR-0081)

### What was built

The round's subject was a guard nobody had ever justified:
`validateRoutes` opens with `spec.routes.size ≤ 1`, while every piece of
the route emission underneath it is indexed by `routeIndex`. That reads
like a cap that outlived the one-route scaffolding it shipped with, so
the survey removed it, compiled a two-route component, and ran the
result in Chromium rather than reasoning about it.

Two routes generate cleanly. Two seed folds, two dispatch functions, two
`listenHash` registrations, two write blocks — all indexed, all naming
their own field's slot. Mount is not where they meet: the seeds write
distinct slots and fall back to their own field's initial, so they are
order-independent. The collision is entirely in the write direction, and
it has two halves. The two `if (changed[field])` blocks sit in the same
commit prologue, so a transaction writing both fields opens both and the
*last* `writeHash` wins. Then one `hashchange` wakes both dispatches —
and because dispatch 0's commit assigns `location.hash` synchronously,
dispatch 1 within that same event reads the hash dispatch 0 just wrote,
not the one the event announced.

What turns that into data loss is the ADR-0063 fallback. A route table is
a *total* function from the hash space: a hash it does not name falls to
its declared-default arm. Each route claims the whole space, so anything
the other route writes is "unknown" to it and resets its field. Mounted
at `#/`, one click on `set mode "on" then set tone "hot"` produced seven
commits and ended with both fields back at their declared defaults and
the URL back at `#/`. So the cap stays, restated as a claim about the
browser rather than about the route table: `location.hash` is one string
with one writer.

The two shapes a future lift would have to take went into the ADR rather
than into code — disjoint sub-namespaces with *partial* tables (which
replaces the unknown-hash fallback every route rests on), or one table
over the tuple of routed fields (which is the cap again with a wider
field, and the only additive one).

Alongside that, the `LRX-TYPE-117` branch accounting was closed. Five new
fixtures — `RouteTwice`, `RouteDerivedField`, `RouteUnfilteredField`,
`RouteDuplicateHash`, `RouteDuplicateLiteral` — each matched on its *own
message* rather than the shared code, so the branches cannot collapse
into one another. The empty-arm branch is unwritable in the surface DSL
(`sepBy1`), so it is witnessed by a hand-built spec in
`Test/Component/Model.lean`, the way the sibling `LRX-TYPE-115` key-arm
guard already is.

Finally, ADR-0080's first open question: `persist right :=
"leanrx-twin-lab.right"` makes Twin Lab a routed field driving two
regions of which exactly one persists.

### Friction encountered

Almost none, and the one thing worth recording is a non-finding. The
worry going in was that persistence would widen `right`'s region record
and break the ADR-0079 slot-asymmetry gates that Twin Lab exists to hold
— `left` at eight slots with its container at 7 against `right` and
`solo` at six with the container at 5. Reading `regionRecords` first
settled it in a minute: the record is `[handle, rows, nextKey, dirty,
pending]` plus count slots plus the filter container plus the child
inventory, and persistence contributes to none of them. The generated
line is byte-identical to what ADR-0080 pinned, and the artifact gate now
says so in a comment so the next reader does not have to re-check.

The survey harness was throwaway on purpose: a scratch component emitted
through `#eval` into a temp directory, served by a twenty-line static
server, driven by Playwright. It never touched the repo's test surface,
and the cap was restored before anything else was written.

### Bugs found

None — which is the answer the round wanted. The cap was doing real work
all along; the finding is that it had no witness and no recorded reason,
and now has both. One branch turned out to be *dead* rather than merely
unwitnessed: `route item targets a field without a declared String
initial` cannot fire, because `Field Γ String` fixes the schema
position's type, `validateValues` forces the value there to name the same
field, and `ScalarLiteral String` has one constructor — so a source at
the routed index always carries a `.string` initial, and a non-source is
caught by the derived-target branch above it. It stays as the `match`'s
total-function fallback, documented rather than witnessed.

The OQ1 combination held in both directions. A `mode` flip runs both twin
sweeps, writes the hash once, and emits no `storage:right:write`, leaving
the stored string byte-equal; a `right` row toggle emits exactly one
`storage:right:write` carrying the drained row and no `route:mode:write`,
leaving the URL where the flip put it. Mounting with a seeded hash *and*
a stored row table settles both in the one hydrate commit: the routed
literal — the union-only `"mixed"` — is applied by that commit's own
sweep to the rows it just mounted, with no hash write, while the two
unpersisted regions mount empty though one of them shares the routed
field.

### Performance observations

Validation-only plus one example module. Every generated artifact outside
Twin Lab is byte-identical, so the benchmark size gate and BENCHMARK.md
stand without re-measurement. Inside Twin Lab, persistence costs one
hydrate function, one serialization loop behind `region_touched_1`, and
two host imports — nothing per route, nothing per filtered region, and no
region-record slot.

### Follow-up issue or commit

`feat(component): seal the one-route cap and witness every route branch
(ADR-0081)` — the five compile-fail fixtures and their harness rows, the
two-span check on the cap's diagnostic, the spec-level empty-arm witness,
Twin Lab's `persist right` with its artifact-gate pins and two browser
tests, the language-guide snippet and prose, the ADR, and this record.
Open: a tuple route as the additive way to route more than one field, and
whether a row write that provably cannot change a selection should still
wake the sweep.
