# ADR-0031: Drop unreachable host declarations from the flattened js-framework-benchmark module

- Status: Accepted
- Date: 2026-08-23

## Context

ADR-0023 flattens the js-framework-benchmark application into one module —
the DOM host and the keyed region host inlined whole, in import order, then
the generated declarations, then the mount statement — and ADR-0024 compacts
that text. Both decisions kept every host declaration: "no function is
tree-shaken", and `BENCHMARK.md` read the size rows as "the shared region
runtime host rather than a tree-shaken lower bound". That was the right
reading while the size result was meant to stand for the repository's hosts
as other examples ship them. It no longer describes what the page fetches:
since ADR-0023 the shipped artifact is one module built for this application,
its hosts are already rewritten (comments, whitespace, `export` keywords,
identifiers) by the build, and after ADR-0028/ADR-0030 it carried 294 raw
bytes of DOM-host functions nothing in the page can call — `childAt`,
`firstChild`, `nextSibling`, `setProperty`, `uniqueId` with its counter, and
`listen` (the benchmark mounts rows with `nextText` and wires clicks through
the two delegated listeners). Every other framework in the upstream suite
ships a bundler's tree-shaken closure of its entry; shipping dead functions
made LeanRx's size row neither the repository hosts (those are the readable
`runtime/` files) nor the application's closure.

## Decision

`LeanRx.Js.Compact.compact` gains an opt-in `prune` step, applied before
renaming: the top-level segments that are roots — any statement, and any
`let`/`const`/`var` whose initializer is not a single literal — stay, and a
top-level `function` declaration or a literal-initialized `let`/`const`/`var`
stays only if a kept segment references its name outside that segment's own
local bindings, transitively. A self-reference keeps nothing alive; a module
with no root keeps nothing. Without `prune` the compactor's output is
unchanged. The benchmark build (`examples/JsFrameworkBenchmarkBuild.lean`)
calls the compactor with `prune := true` over the flattened text, so the
shipped module is the mount statement's closure over the inlined hosts and
the generated declarations; `runtime/leanrx_dom.mjs`, `leanrx_region.mjs`,
every other example's served hosts, `leanrx doctor`'s host check, the runtime
ABI, the Lean model, and the backend are unchanged.

The size policy reads accordingly: the size rows are the bytes the page
fetches, which since ADR-0023 is one application-specific module, and that
module contains exactly the host code reachable from the application's entry
(not a hand-picked subset, and not the unflattened hosts); the hosts the
application imports are still shipped whole at the module level in every
non-flattened example.

## Consequences

`main.mjs` shrinks from 9,236 raw / 3,339 upstream-style Brotli bytes to
8,942 / 3,251 (the application from 10,902 / 3,699 to 10,608 / 3,611, against
Solid's single 11,563 / 4,358-byte module); the dropped declarations are the
six unused DOM-host functions and `uniqueId`'s counter. Nothing the page runs
changes, so the CPU rows are unaffected. The pruned-away functions remain in
`runtime/leanrx_dom.mjs` for the examples that import them. The compactor's
golden test gains the pruned form of its fixture, a transitive-reachability
case (an effectful `const` as a root, a declaration referenced only from a
dead declaration, a self-recursive dead function), and the no-root case;
`./scripts/check.sh` syntax-checks and runs the pruned module through the
benchmark browser gate and compares the size report with the recorded
baseline.
