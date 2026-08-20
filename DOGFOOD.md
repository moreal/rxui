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

One `Int` state field, `doubled` and `parity` derived values, two click events,
four scalar text sinks (including hostile generated text), deterministic graph/ESM/manifest output, two independent
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
the permanent regression and proves `<img ... onerror>` remains a text node.
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
by native Lean and observed in Chromium after a synthetic invalid submit proves
that disabled-button state is not the sole guard.

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
