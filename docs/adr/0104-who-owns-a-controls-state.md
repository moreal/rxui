# ADR-0104: Who owns a control's state

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0103 closed three questions and named a fourth. The one it named is the
row template, and it named it from three directions at once — 14.83 µs to
render a row, 156 ns per node to detach one, 2.06 µs of ADR-0063 history write
per row in the document — with the same observation attached to all three: a
row carrying a form control costs the browser more than a row carrying text.
Its open question ended with a scout and a bill:

> `autocomplete="off"` is exactly that sentence, said to the browser. […]
> Nothing here takes it: this is a scout, and the round that takes it owes a
> paired measurement on the real emission and a statement of what a user
> loses.

This round pays both. It also answers the render-axis puzzle ADR-0103 recorded
without explaining — a six-node row carrying a `<button>` cost more than a
seven-node row of `<span>`s — and the answer turns out to be that the three
axes do not order the controls the same way at all.

### The harness

ADR-0099's, at ADR-0101's settings, unchanged: `performance.now()` probes cut
mechanically into the *generated* Toggle Lab module with an exact-count
assertion on both anchors of every probe, COOP/COEP so the clock is 5 µs, keys
pinned so a re-seed is a retained reconcile, and the seed walking the table to
put every ADR-0086 display cell and the DOM into the same all-shown state
before a timed flip starts. Twelve probes, and **all twelve matched exactly
sixteen times on the first run in both dists** — the second round running
since ADR-0102 moved the record slots under nine of them.

## The measurement

### 1. What the browser charges for, per axis

Framework-free, ten thousand rows, one row template per column, paired with
ABBA inside every pass and an A/A control read first in every cell. Three
independent measurements: the ADR-0063 history write (`location.hash =` with
the table already settled) over eleven shapes, and the show direction (the
slope `(T(k=2000) − T(k=1000))/1000`, which cancels ADR-0103's `1.045 µs · N`
term) and the detach (every row out, write and forced layout together) over
nine of them — a radio and an `<input type="hidden">` are history-write
questions only.

| row template | nodes | history write | render, per row shown | detach, all out |
| --- | ---: | ---: | ---: | ---: |
| text only | 2 | 0.335 | 5.83 µs | 6.94 |
| one `<span>` | 3 | 0.455 | 7.04 µs | 8.36 |
| three `<span>` | 7 | 0.875 | 7.90 µs | 13.28 |
| `<span>` + `<button>` | 5 | 0.685 | 8.73 µs | 11.21 |
| `<span>` + checkbox | 4 | **17.565** | 7.42 µs | 10.07 |
| `<span>` + radio | 4 | **17.960** | — | — |
| `<span>` + `type="hidden"` | 4 | 0.985 | — | — |
| `<span>` + text input | 4 | **9.720** | 12.31 µs | 15.43 |
| `<span>` + `<textarea>` | 5 | **10.135** | 12.92 µs | 15.76 |
| `<span>` + `<select>` | 6 | **35.830** | 26.92 µs | 27.62 |
| Toggle Lab's row | 11 | **19.550** | 15.32 µs | 21.99 |

**The three axes disagree, and that is the finding.** Reading the marginal
cost of one element out of the neighbouring rows:

- The **history write** is charged per *stateful* form control and nothing
  else. A `<button>` is free (0.685 ms is what five nodes of markup cost), and
  so is `<input type="hidden">` — it carries a value and this browser saves
  none of it. A checkbox is **1.71 µs**, a radio 1.75,
  a text input 0.93, a `<select>` 3.54. A `<span>` and its text are 0.02 µs.
- The **render** is charged per *rendered widget*. A `<span>` plus its text is
  0.43 µs; a `<button>` plus its text is **1.69 µs**, four times as much; a
  checkbox is 0.38 µs, no worse than a span; a text input is **5.27 µs**, a
  `<textarea>` 5.88 and a `<select>` **19.88**.
- The **detach** is nearly pure node count — `450 ns/row + 126 ns/node` fits
  the text, span and three-span rows — plus a surcharge for a control holding
  editable state: a button and a checkbox land within 0.06 µs of the fit, a
  text input is +0.59, a `<textarea>` +0.50 and a `<select>` +1.56.

So **ADR-0103's six-node button row beat its seven-node span row because a
`<button>` renders for four `<span>`s**, and the same button is free on the
axis ADR-0103 called it expensive on. The checkbox is the mirror image: the
cheapest control to render and, after `<select>` and radio, the most expensive
to save. Toggle Lab's row is a checkbox and two buttons, which is why it is
19.55 ms of history write and only 15.32 µs of render.

### 2. The attribute, paired, on all three axes

`autocomplete="off"` is the platform's word for "this control's state is not
worth saving". Same harness, same cells, arms differing only in that
attribute on every control the row carries:

| row template | A/A | plain | `autocomplete="off"` | ratio |
| --- | ---: | ---: | ---: | ---: |
| checkbox, 10 000 rows | 0.981× | 17.565 | 1.035 | **16.97×** |
| checkbox, 1 000 rows | 0.984× | 1.605 | 0.225 | 7.13× |
| radio, 10 000 rows | 1.002× | 17.960 | 1.165 | 15.42× |
| `<select>`, 10 000 rows | 0.987× | 35.830 | 5.980 | 5.99× |
| text input, 10 000 rows | 1.004× | 9.720 | 2.275 | 4.27× |
| `<textarea>`, 10 000 rows | 0.961× | 10.135 | 2.655 | 3.82× |
| Toggle Lab's row, 10 000 | 0.989× | 19.550 | 2.335 | **8.37×** |
| Toggle Lab's row, 1 000 | 0.973× | 1.785 | 0.415 | 4.30× |
| text only, 10 000 rows | 1.015× | 0.335 | 0.345 | 0.97× |
| `<button>`, 10 000 rows | 1.015× | 0.685 | 0.660 | 1.04× |

and it moves **neither of the other two axes**, which is what makes it worth
emitting rather than trading:

| row template | show A/A | show | detach A/A | detach |
| --- | ---: | ---: | ---: | ---: |
| checkbox | 0.985× | 1.015× | 0.997× | 0.988× |
| text input | 1.014× | 1.001× | 0.996× | 0.990× |
| `<select>` | 0.999× | 1.003× | 0.999× | 1.013× |
| `<textarea>` | 0.989× | 0.941× | 1.001× | 0.990× |
| `<button>` | 0.990× | 1.026× | 1.004× | 0.993× |
| Toggle Lab's row | 1.013× | 0.996× | 1.005× | 0.994× |

Eleven of the twelve cells are inside their own A/A band; the twelfth is the
`<textarea>` show at 0.941× against a control of 0.989×, a 5% loss on the one
shape in the table `HtmlTag` cannot emit. Every shape the language *can* emit
is inside its control on both axes. The scout's 17× survives being measured
properly and is 8.37× on the shape the language actually emits.

### 3. What it would cost: the browser's own restoration

Before emitting it, what the attribute turns off had to be found out rather
than assumed, because the platform's rules for *when* form state is restored
are not the same as the rules for when it is saved. Two arms of every control
— parse-time and created by script after load, which is every element LeanRx
emits — filled by real user input, then a reload and then a back/forward:

| control | typed | after `reload()` | after `goBack()` |
| --- | --- | --- | --- |
| parse-time text | `typed-parse-on` | *(empty)* | `typed-parse-on` |
| parse-time text, `off` | `typed-parse-off` | *(empty)* | *(empty)* |
| script-built text | `typed-js-on` | *(empty)* | `typed-js-on` |
| script-built text, `off` | `typed-js-off` | *(empty)* | *(empty)* |
| parse-time checkbox | checked | unchecked | checked |
| script-built checkbox | checked | unchecked | checked |
| either, `off` | checked | unchecked | unchecked |

Two facts, one of them the opposite of what was expected. **A reload restores
nothing, for anyone** — not a parse-time control, not a script-built one, with
or without the attribute — so the reload half of ADR-0103's open question
costs zero by measurement. (An ordinary navigation reload in this Chromium
build; the platform does not specify restoration on that path, so this is a
browser fact and not a contract, which is why it was measured rather than
read.) And **a back/forward traversal that re-creates the
document does restore, and it reaches script-built controls too**: the
document being built entirely by `mount()` after load buys no exemption. That
is what the 2.06 µs per row is being paid for, and it is real.

The third measurement is the one that decides it. A control whose value the
program owns is written from the state cell at mount and rewritten by every
update sweep (ADR-0038, ADR-0047, ADR-0060). Give such a control a mount value
of `from-state`, let the user type `user-typed` over it without the program
storing that, and traverse back:

| control | the cell says | mount writes | after `goBack()` | |
| --- | --- | --- | --- | --- |
| text, plain | `from-state` | `from-state` | `user-typed` | **diverges** |
| text, `off` | `from-state` | `from-state` | `from-state` | agrees |
| checkbox, plain | `true` | checked | unchecked | **diverges** |
| checkbox, `off` | `true` | checked | checked | agrees |

**The browser's restoration is not redundant for an owned control; it is
contradictory.** It lands *after* the mount has written the owned value and
leaves the DOM disagreeing with the cell that owns it — the ADR-0060
cache-DOM divergence class, arriving through the one door the compiler had
not closed. So the attribute is not only 8× cheaper on the history write; on
an owned control it is the correct thing to say regardless of cost.

What it does cost is stated plainly: on an owned **text** input the browser
will no longer offer autofill suggestions from previously entered values, and
will no longer bring a user's un-committed typing back on a traversal — which
is exactly the divergence above, so a program that wants that typing back owes
it to its own state, where ADR-0063 already persists it. On a control the
program does **not** own, nothing changes, because the rule does not touch it.
The bfcache path was not reachable here (`pageshow.persisted` stayed `false`
with the cache enabled by flag, so every traversal this harness produced
re-created the document); by the platform's contract that path returns the
live document rather than a restored form state, so the attribute is not
consulted on it.

### 4. The real emission, paired

Two dists of the generated Toggle Lab module differing in exactly four
`setAttribute` calls, one page each plus a second page of the baseline as the
A/A control, ABBA inside every pass, per-cell minima, medians of the pass
values. Milliseconds; `route` is the ADR-0063 history-write probe segment.

| N / k | A/A | route, hide | with the attribute | ratio | commit, hide | round trip |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 000 / 1 000 | 0.994× | 19.90 | 3.53 | **5.637×** | 23.37 → 6.89 | 77.41 → 47.27 |
| 10 000 / 5 000 prefix | 1.071× | 20.19 | 3.45 | 5.854× | 35.17 → 18.46 | 163.53 → 137.62 |
| 10 000 / 5 000 spread | 0.987× | 20.12 | 3.59 | 5.611× | 37.47 → 20.95 | 170.46 → 145.79 |
| 10 000 / 10 000 | 0.961× | 19.84 | 3.52 | 5.638× | 49.96 → 34.00 | 267.40 → 253.63 |
| 1 000 / 500 | 1.025× | 1.90 | 0.45 | 4.233× | 3.36 → 1.90 | 15.47 → 13.25 |
| 1 000 / 1 000 | 0.981× | 1.87 | 0.49 | 3.806× | 4.86 → 3.44 | 26.12 → 25.01 |

**ADR-0103's law is replaced.** The history write was `2.00 µs` per row in the
document at the moment it ran; it is now `0.34 µs · rows + 0.15 ms`, a 5.9× on
the row term, fitted across the same two counts and confirmed at every
intermediate document size the flip itself produces — the show direction
writes with `N − k` rows present and reads 3.26, 1.75, 2.22 and 0.19 ms
against 16.40, 9.02, 10.17 and 0.35.

The commit and the click follow it exactly and nothing else moves. At
10 000 / 1 000 the commit falls 23.37 → 6.89 ms (**3.39×**) and the residue
either side of the route probe is 3.47 → 3.36; at `k` = `N` the commit falls
49.96 → 34.00 and the residue is 30.12 → 30.48. The whole round trip is
**1.638×** at `k` = 1 000, and the 30.1 ms it drops is the two route writes'
16.37 + 13.14 to within 0.7 ms. Where the sweep dominates — `k` = `N` — the
route saving is still 16.5 ms and the round trip drops 13.8 of 267, which is
**1.054×**, and that is the correct shape:
this lowers a term that does not grow with `k`, so it matters most to the
flips that move the fewest rows, and **it is not a filter's number at all**.
Every commit that writes the hash pays it, and a routed field's write is the
one thing on that path a component cannot make smaller by touching fewer rows.

### 5. The mount, measured rather than assumed

ADR-0101 measured one static attribute per row as free at mount. This round
ships one, so it is measured on the real emission instead of inherited:

| rows | A/A, click | click | A/A, reconcile | reconcile segment |
| ---: | ---: | ---: | ---: | ---: |
| 10 000 | 0.979× | 246.75 → 247.17, 0.998× | 0.953× | 31.77 → 33.70, 0.943× |
| 1 000 | 0.999× | 23.71 → 23.27, 1.019× | 0.995× | 3.09 → 3.11, 0.997× |
| 100 | 1.002× | 2.50 → 2.60, 0.962× | 0.985× | 0.32 → 0.34, 0.970× |

Every click cell is inside its own control. The reconcile segment's
ten-thousand-row cell sits at the edge of its own drift rather than inside it
(0.943× against 0.953×), which is the honest reading: the extra call is one
`setAttribute` per row, its 1.9 ms is the same size as that segment's
page-to-page variation, and the two cannot be separated. Against the 247 ms
click it is not visible at all.

## Decision

**The compiler declares ownership of the control state it owns.** An element
gets one static `autocomplete="off"` exactly when the program writes its
`value` or `checked`:

- in row scope, an element carrying an ADR-0047/0049 `RowReflect` — the row
  checkbox's `checked={done == "true"}`, the branch editor's `value={draft}`;
- in component scope, an element carrying an ADR-0038 `PropBinding` — a
  controlled `value={rx% draft}` or `checked={rx% loud}` — or an ADR-0060
  `checkedIfEmpty` attribute selection, whose checkbox follows a region count.

Everything else is untouched, and the boundary is a real one rather than a
tag test: Nest Lab's roster input carries an `onInput` and no `value`, so the
DOM owns its text, the program makes no claim about it, and the browser keeps
its restoration.

The rule is one function, `StaticAttr.withOwnedState`, applied at the two
places an element's static attributes are emitted, and `StaticAttr.ownedState`
is the one constructor of the sealed attribute vocabulary that the JSX surface
has no spelling for. It cannot land on a non-control by construction: every one
of the three subjects is already rejected on anything but a native `input` —
"reflected properties require a native input element", "a row `value`
reflection requires a native input element", "a checked reflection over a
region count requires a `type="checkbox"` input element" — so the attribute
follows a check the component model already performs rather than adding a tag
test of its own. **No host export, no record slot, no statement order and
no ABI**: `runtimeAbi` stays 20 and the four runtime host modules are
byte-identical, because an attribute is not a host concern.

## Consequences

- **Five generated modules grow and nine do not.** Toggle Lab +187 bytes (four
  sites: the row checkbox, the branch editor, the new-todo input, the
  toggle-all box), Echo Lab +141 (three), Branch Lab +46, Mix Lab +46, Twin
  Lab +46 (one each). Counter, Diamond, Filter Lab, **Nest Lab**, Dependent
  Tabs, Temperature, Validated Form, TodoMVC, Notes, Issue Browser, Data Grid,
  the docs site, the expression playground and the js-framework-benchmark
  bundle are byte-identical, so **the size baseline does not move**. Every
  changed line is an added `setAttribute(…, "autocomplete", "off")`; no
  existing line moved in any bundle. Every manifest is byte-identical too,
  `graphHash` included: the attribute is a property of how an element mounts,
  not of the reactive graph, so nothing the hash covers changed.
- **The witness is a count, not a substring.** The Toggle Lab artifact gate
  pins all four emitted sequences *and* asserts the module declares exactly
  four — a fifth would mean the rule had started paying for a control the
  program does not own, a third that an owned one had stopped declaring it —
  and the Echo Lab gate does the same at three. The Nest Lab gate carries the
  negative: its module contains no `autocomplete` at all, and its uncontrolled
  rename input is pinned in place. A browser test walks the DOM count through
  a mount (2 static controls), three appends (5), a branch entry and Escape
  (6 and back to 5), and a filter flip (3, then 5), which is the same count
  the history write is charged for, since ADR-0102 detached the rows.
- **A model-level test states the law.** `Test/View/Model.lean` pins the
  attribute's spelling, its last position in the list, the two-case
  `withOwnedState` law, `checkedIfEmpty` owning control state while
  `hiddenIfEmpty` does not, and Counter — which reflects nothing — carrying it
  nowhere in its mount tree.
- **The bespoke backends are out of scope and say so.** Todo, Notes, Issue
  Browser, Data Grid, Temperature, Validated Form, Dependent Tabs and the
  benchmark hand-write their DOM through their own emitters and none of them
  gained the attribute. The rule lives in the checked-component pipeline,
  which is where the ownership claim it encodes is checked.

## Open questions

1. **The hand-written backends make the same claim and do not say it.**
   Validated Form's inputs are controlled by the same ADR-0038 mechanism and
   Temperature's are the original controlled-input dogfood, but both emit
   through bespoke backends that never see `StaticAttr`. Neither writes a
   route today, so neither pays the history write; the divergence measured in
   §3 is theirs anyway, on any traversal a user makes. What is unclear is
   whether they are worth changing or worth deleting, since every one of them
   exists to be the thing the generic backend replaced.
2. **`<select>` costs 26.92 µs to render and 3.56 µs to save, and the language
   cannot emit one.** `HtmlTag` has no `select` and `InputType` has only
   `text` and `checkbox`, so the two most expensive controls the platform
   offers are unreachable. That is not an argument for adding them; it is a
   number to have ready when someone does, and the `autocomplete` rule already
   generalises to them unchanged.
3. **Showing fewer rows than the filter selects.** ADR-0103's second open
   question is untouched and is now the largest term of a flip at every `k`:
   with the history write at 0.34 µs per row displayed, what is left is
   `1.045 µs · N + 14.83 µs · k` of style and layout, and the only lowering
   that would move it is a region that renders a window of its selection. It
   remains a language round: a region's rows would stop being *the* rows.
4. **`swapAt` and the filter still cannot meet.** ADR-0102's second open
   question, third round standing: no emission puts a swap and a filter on one
   region, so the displayed-anchor branch is exercised only by the host gate.
