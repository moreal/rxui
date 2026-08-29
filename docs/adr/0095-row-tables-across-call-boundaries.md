# ADR-0095: A row table stays a row table when it becomes a parameter

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0093 audits every module the component backend emits for the shapes that
could break a region's row table, and ADR-0094 pinned the one boundary that
audit stops at on the host side. ADR-0094 then wrote down the boundary that
was left:

> **`$lrx_row_seek`'s body is checked by neither side.** ADR-0093's R1 lets a
> row table cross into the generated search, and inside that function the table
> is a parameter named `rows` — not spelled `regions[r][1]`, so R1 does not
> reach it, and not a host export, so this contract does not either. R4's
> parameter half forbids `rows[i][0] = …`, but a `rows.sort()` or
> `rows.splice(…)` in the helper passes both — verified, not read.

The verification stands and this round re-ran it: with `rows["sort"]()` as the
helper's first statement the pre-change emitter puts the sort in Toggle Lab's
bundle and `lake exe leanrx_toggle_js` exits zero. `$lrx_row_seek` is a binary
search over a table that must be strictly ascending in `row[0]`, so a sort by
the tuple's *natural* order — which compares slot 0 as a string once a region
has minted ten keys — or a two-row `splice`, or an alias handed onward, breaks
the very order the function exists to exploit, inside the function that exploits
it.

The gap is small only by accident. R1's argument allowance is not a special case
for one helper: it is the general permission for a table to become an argument,
and the audit's rules are all phrased over the expression `regions[r][1]`. The
instant a table is bound to a parameter name, seven of the eight rules stop
having a subject.

### What the existing gates catch, and what they do not

Nothing else covers it, and it is worth being exact about why, because three
gates look like they might.

* **The codegen gate's double-generate `diff -ru`** proves the emitter is
  deterministic. A helper that sorts its argument is emitted identically both
  times, so the diff is empty and the gate is green.
* **The artifact tests and manifest assertions** pin the bundle's shape and
  digests against what the emitter currently produces. They move with the
  emitter: change the helper, regenerate, and they pin the new bytes.
* **`LRX-BE-018`**, the module validator, is a scoping and well-formedness rule.
  `rows["sort"]()` inside a function whose parameter is `rows` is perfectly
  well-scoped.
* **The ADR-0092 browser gate** would catch it — if a cell happened to exercise
  a region with more than nine rows, since below ten a numeric sort and a
  natural sort agree. That is the argument ADR-0093 already made about
  witnesses over an open surface, sharpened: the emission that breaks the order
  is the emission nobody wrote a cell for, and here even the cells that exist
  can be silently the wrong size.
* **ADR-0094's contract** guards arrays that cross into `runtime/`. A generated
  helper is not a host export and never crosses that boundary.

So the variant caught today is exactly one: a key slot written as `rows[0] = …`,
by R4's parameter half, which forbids writing slot 0 of *any* parameter and
therefore hits a row table's first element by coincidence rather than on
purpose. Everything else — `rows.sort()`, `rows.reverse()`, `rows.splice(i, 2)`,
`rows.unshift(row)`, `rows.push(row)`, `const t = rows`, `return rows`,
`rows[i] = rows[j]`, `rows[i][0] = k` — passes every gate the repo has.

## Decision

**Pay, by widening R0 rather than by adding a rule.** The audit computes, before
it applies any rule, the set of `(function, argument position)` pairs that
receive a row table anywhere in the module, and treats the matching parameters
as row tables. R0's claim becomes:

> Every row table in the module is named. Two spellings and no others:
> `regions[r][1]`, and a parameter of a module function that some call site
> hands one to.

Everything else is unchanged. There is **no ninth rule and no new diagnostic
code**: the eight rules are already phrased over "a row table", and the round's
whole content is that the phrase now denotes what it always meant. Rejections
stay `LRX-BE-036` and keep naming the rule and the function; only the subject
half of the message is new — `the row table parameter 'rows'` where it used to
say `region 0's row table`.

### Which layer, and why not the narrower one

The narrow option was to audit `$lrx_row_seek`'s body with its first parameter
known to be a table — one line, since the helper is emitted by one Lean function
and called from one place. It is rejected for the reason ADR-0093 rejected a
narrowed emission vocabulary: it constrains the path that opts in. The second
helper — a shared removal, a sweep, a comparison — inherits nothing, and its
author gets no diagnostic, only a convention they never read. A rule that names
`$lrx_row_seek` is a rule about today's emitter, and ADR-0093's entire argument
for the audit was that its rules must be about *JavaScript*, not about the
sites that happen to exist.

The general rule costs one traversal and a fixpoint. It is also strictly the
same rule the audit already had: a table may occupy an approved position, and
"an argument" is one of them, so what the round really does is stop the
approval from being a hole by following the table through it.

### Propagation is a least fixpoint, not one step

One step — taint the parameters that receive `regions[r][1]` directly — is
sound, because a table forwarded from one helper to a second would be rejected
under R1 at the forwarding call rather than allowed. It is also arbitrary: two
helpers is not a stranger emission than one, and a rule whose reach is "one
call" would have to be renegotiated by the first round that writes the second
helper.

The fixpoint costs a loop. `sweep` reads every function with the pairs known so
far and adds the ones its body raises; `propagate` iterates until nothing is
added. Every pass that changes anything adds at least one pair, and the pairs
are bounded by the module's total parameter count, so that count is a budget
that cannot be exhausted. `audit` re-sweeps once anyway and rejects under R0 if
the set is not stable, so a budget that ever *were* wrong would fail closed
rather than approve a call site whose callee it never audited.

### What the rules say at the new subject

Six of the eight read at a parameter table verbatim. Three deserve a sentence,
because a parameter table has no region, and that is not a gap in the rules but
the reason two of them cannot be satisfied there.

* **R2** requires a pushed row's key to be `regions[r][2]` for the table's own
  region. A parameter has no region, so there is no counter to name and no
  legal push: a parameter table cannot be pushed onto at all. The emission pays
  nothing — no generated helper pushes — and the alternative would be to invent
  a way to spell a counter the function cannot see.
* **R5**'s target is a region slot, so a whole-table rebuild cannot be installed
  through a parameter either.
* **R3** is the one mutation that survives, and it survives on merit: a
  two-argument single-row `splice` is order-preserving whichever region the
  table belongs to. So R3 stays a shape rule at both subjects rather than
  becoming a ban, and a future helper that removes a row inherits the rule
  instead of needing a new one.
* **R4** gains the spellings its parameter half could never see. That half
  forbids writing slot 0 of any parameter; it says nothing about `rows[i] = …`
  or `rows[i][0] = …`, which are the swap and the re-key, and those are now
  rejected because the subject is a table.
* **R1** gains one clarification it needed anyway: a table may be handed to a
  function *this module declares*, because that is what makes the parameter a
  subject. An imported callee has no body to audit, so handing it a table is a
  rejection, not a site. `createKeyedRegion`'s handle keeps its own allowance
  and its own gate (ADR-0094).

### The diagnostic

Unchanged: `LRX-BE-036`, one code, raised by the component backend at emission,
with the rule tag and the function as the message's subject.

```
row order audit (R1) in '$lrx_row_seek': 'sort' is called on the row table
  parameter 'rows'
row order audit (R1) in '$lrx_row_trim': 'sort' is called on the row table
  parameter 'trim_rows'
```

The second is the two-call case, and it is worth showing because the message
names a function that never mentions a region.

### Cost

**Layer**: the compiler, in the audit that already runs. **Subject**: every
module the component backend emits. **Price**: the audit of Toggle Lab — the
largest generated module, 168 kB and 4 700 printed lines — goes from **666 µs
to 1 483 µs**, measured compiled over 200 repetitions inside
`lake exe leanrx_test`. The extra 817 µs is three traversals: two propagation
sweeps (one to find the pairs, one to see that nothing was added) and the
stability re-sweep, each cheaper than the audit proper because it collects
without an `Except` and without the R5 census. The wall time of
`lake exe leanrx_toggle_js` is 0.54–0.59 s, unchanged and three orders of
magnitude above the delta; across the twenty component-backend generator runs
in `scripts/check_component_codegen.sh` the audit totals under 30 ms.

**Zero output bytes.** The audit reads the module and returns.

### Witness

The ADR-0093 witness goes from 24 cases to 43, all over the module
`Backend.Component.emit` really produces for Toggle Lab. Sixteen of the
nineteen new ones are rejections and every one of them was **accepted** before
this round.

Thirteen inject into `$lrx_row_seek` itself, which receives `regions[0][1]` at
seven call sites: a `sort`, a `reverse`, an `unshift`, an alias, a `return` of
the table and a rebinding of the parameter (R1/R4); a push with a literal row
and a push with one of the table's own `for`-of rows (R2, in both spellings a
push has, because the second is the shape a kept-filter rebuild wears); a
two-row `splice` and an inserting three-argument `splice` (R3), against an
accepted single-row removal; and the swap and the re-key that R4's parameter
half could not see. Two more go into the dispatch, where the table is still
spelled `regions[0][1]`: a table replaced by an ordinary binding (R5) and a
table handed to an imported function (R1), which is the position the new
allowance had to be careful not to open.

Four watch the propagation cross **two** calls. A second helper is appended to
the real module and `$lrx_row_seek` is made to forward its parameter to it; the
second helper sorting the table it never asked for, and re-keying one of its
rows, are rejected naming *its* parameter, while a second helper that only reads
is accepted. The fourth pins the rule to call sites rather than to names: the
same helper body, with nothing handing it a table, is accepted — a parameter is
a row table because somebody passed one, not because it is called `rows`.

Both directions were checked against deliberate breakage rather than assumed to
bite.

- *The emitter, broken three ways.* `rows["sort"]()` and `rows["splice"](0, 2)`
  as the first statement of `rowSeekFunction` each make
  `lake exe leanrx_toggle_js` exit non-zero under `LRX-BE-036` (R1) and (R3) —
  the first is literally ADR-0094 OQ1's injection, which previously reached the
  bundle. Third, a second emitted helper `$lrx_row_trim` that sorts its
  argument, with `$lrx_row_seek` forwarding `rows` to it: rejected as
  `row order audit (R1) in '$lrx_row_trim'`, so the fixpoint is wired into the
  path that produces bundles and not only into the witness.
- *The audit, broken four ways.* Deleting R1's parameter-escape rejection makes
  the alias pass; deleting the guard that keeps a rebuild push from being read
  as one when the target is a parameter table makes the own-row push pass. Both
  turn the witness red naming the case. The two vacuity modes — the propagation
  collecting nothing, and `tableOf?` blinded to parameters — do **not** pass
  quietly: each makes the *real* Toggle Lab emission fail, the first under R0's
  stability check and the second under R1, because the audit's two halves then
  disagree about a parameter the emitter really passes a table to. The fail-safe
  direction is to reject.

## Consequences

- **Every generated file in every bundle is byte-identical.** Proven by
  generating Toggle, Mix, Twin, Branch and Nest Lab from the pre-change emitter
  under `git stash`, regenerating after, dereferencing both symlinked bundles
  with `cp -RL` and comparing with `diff -rq`: no difference in any `.mjs`,
  `.graph.json` or `.manifest.json`, in any of the five, and none in the
  bundled `leanrx_dom.mjs`, `leanrx_form_events.mjs` or `leanrx_region.mjs`
  either. The only file that differs is `.leanrx-bundle-owner`, which names the
  output directory by construction. The codegen gate's double-generate
  `diff -ru` and each artifact test's manifest assertion pin the claim on every
  generator run; the benchmark size gate, its manifest and BENCHMARK.md are
  untouched.
- **No host change and no ABI move**: `runtimeAbi` stays **17**. Nothing under
  `runtime/` changes and the audit exports nothing at runtime.
- **ADR-0094 OQ1 is closed.** Its replacement obligation is narrower and stated
  below: the audit follows a table across calls inside one module, and a module
  is where it stops.
- The hand-written backends are unaffected for ADR-0093's reason: they carry no
  region record and no `$lrx_row_seek`, so neither ADR-0092's search nor this
  audit applies to them.

## Open questions

1. **The audit's reach is one module.** R0's second clause follows a table into
   functions the same module declares; a table handed to an *import* is
   rejected rather than followed, which is safe and is also the whole of the
   answer. Today no emission wants to hand a row table across a module
   boundary — ADR-0068's child composition passes props, not tables — and if
   one ever does, it would need either a cross-module summary or a host-style
   contract at the import, and neither is a step this round could take on
   speculation.
2. **A parameter table is region-less on purpose, and R2 and R5 pay for it.**
   The audit could carry the region through when every call site of a helper
   passes the same one, which would let a future helper push a row. It would
   also make the rules' subject a lattice instead of a name, and no emission
   asks for it. A round that wants a helper to append has to reopen this.
3. **`storageSet` and the `join` are the floor, at 35% each** (ADR-0087 OQ1,
   ADR-0093 OQ2, ADR-0094 OQ3, unmoved).
4. **A shared predicate pass is per commit, so it is not a cache**
   (ADR-0088 OQ3, ADR-0094 OQ4, unmoved).
