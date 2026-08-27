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
