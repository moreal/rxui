# ADR-0028: Bump the internal runtime ABI for text-slot traversal in the DOM host

- Status: Accepted
- Date: 2026-08-23

## Context

After ADR-0027 the js-framework-benchmark's create-10,000 handler costs about
1.2 ms more script than the upstream vanilla implementation (paired CDP
sampling profile, 24 interleaved clicks per page, warm JIT) and the whole
difference is garbage collection (about +1.3 to +2 ms) plus the two per-row
delegated-action attributes in the cloned template (about +0.6 ms in
`cloneNode`); every other self time is level. The young-generation volume of
that handler is dominated on both sides by DOM wrappers: a row mount reads
`firstChild`/`nextSibling` four times to reach the id cell's text and the
select link's text, so every row allocates six wrapper objects (`tr`, `td`,
text, `td`, `a`, text), all of which survive while the node is in the
document. Vanilla does the same. Only two of the six are ever used again.
The per-row entry object, the handle array, the key string, and the BigInt id
together are a smaller share and removing the handle array alone measured
within noise.

A `TreeWalker` with `SHOW_TEXT` reaches the same two text nodes with three
calls (`currentNode` set, `nextNode`, `nextNode`) and wraps only the nodes it
returns; the elements it steps over are never wrapped. Measured with the
paired harness (two dists, 12 clicks per page, 10 rounds): create 10,000 is
1.3 ms faster and now level with vanilla (−0.15 ms paired), create 1,000 is
0.12 ms faster, and garbage collection falls by about 1.7 ms per click in the
profile. A walker created per row instead of one shared walker costs 1.0 ms
more than the shared one (rejected); setting `currentNode` per call instead
of a stateful "continue from the last result" pair measures the same, so the
stateless form is adopted.

## Decision

The internal JavaScript runtime ABI becomes version 14 for every artifact.

The DOM host gains `nextText(node)`: the Text node that follows `node` in
document order (descendants first), or `null` — exactly
`TreeWalker(SHOW_TEXT).nextNode()` from `node`, through one lazily created
walker rooted at the host's document whose `currentNode` is the last returned
node. It does not stop at `node`'s subtree: the walk continues into following
siblings and ancestors' siblings until the tree's top, so generated code uses
it only where a static template guarantees the text slots (and in that order)
it addresses. `firstChild`, `nextSibling`, and the rest of the DOM host are
unchanged for the other backends.

The js-framework-benchmark backend mounts a row as `cloneTemplate`, `setKey`,
`nextText(root)` (the id cell's text), `nextText(idText)` (the select link's
text), and the two `setText` writes; it no longer imports `firstChild` or
`nextSibling`. The Lean model, the region host, and every other operation are
unchanged.

## Consequences

ABI-13 and ABI-14 artifacts/hosts must not be mixed. All manifests move to
version 14. Each benchmark row allocates three DOM wrappers instead of six, so
the create and append paths allocate and retain less (the upstream memory
rows should move down slightly) and the mount path makes six binding calls
instead of eight. The shared walker keeps the last returned text node (and
hence its row) reachable until the next `nextText` call or page unload; that
is one row, documented in the host comment. The DOM host and the flattened
benchmark module grow by the helper, so the size baseline moves accordingly.
Other backends keep the `firstChild`/`nextSibling` navigation they emit today
and may adopt `nextText` where their templates have the same shape.

## Validation

The counter browser suite, which serves the DOM host directly, checks
`nextText` on real DOM: the first two text slots of a detached row template
in order, `null` at the end of a detached subtree, comment and nested-element
skipping, and that the walk leaves a subtree that holds no further text. The
js-framework-benchmark browser gate exercises the mounted rows' id and label
texts, keys, selection, swap, and removal through the new mount path; the
size gate and the upstream run record the results in `BENCHMARK.md`.
