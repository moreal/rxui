# Backend support matrix

This matrix describes the implemented controlled browser backend. A green native
Lean definition alone does not imply browser support. Unsupported staged terms
must fail lowering; they are never silently interpreted by a Lean runtime in JS.

## How to read this matrix

| Label | Meaning |
|---|---|
| supported | accepted by the generic checked component/backend contract |
| checked dependent context | available only through a named typed API such as Tabs |
| specialized dogfood | implemented and tested for a repository application, not generalized syntax |
| experimental | intentionally opt-in and not the default semantics |
| unsupported | no public lowering; use must fail instead of escaping to arbitrary JavaScript |

There are three separate questions for any feature: can Lean represent it, can a
LeanRx checker accept it, and can the selected backend lower it? Only the last
two establish browser support. When they differ, diagnostics identify the phase:

| Prefix | Boundary |
|---|---|
| `LRX-RX-*` / `LRX-ELAB-*` | staged expression or surface elaboration |
| `LRX-TYPE-*` / `LRX-VIEW-*` | typed component and safe-view validation |
| `LRX-GRAPH-*` | dependency graph construction or scheduling |
| `LRX-BE-*` | Reactive IR or JavaScript backend lowering |
| `LRX-PORT-*` / `LRX-HOST-*` | artifact publication or browser-host contract |

## Scalar runtime values

| Lean value | JavaScript representation | Equality plan | Status |
|---|---|---|---|
| `Bool` | Boolean | strict | supported |
| `String` | String | strict | supported |
| `Int` | BigInt | BigInt/strict | supported |
| `Nat` | non-negative BigInt | BigInt/strict | supported with foreign-boundary validation |
| `Vector α n` | Array of supported `α` | element plan | checked dependent contexts |
| `Fin n` | bounded non-negative integer representation | strict | checked dependent contexts |
| functions, `IO`, arbitrary structures | none | none | unsupported |

Port/manifest records and lists use separate nominal metadata. They do not reopen
the scalar `RuntimeTypeId` or reactive equality mapping.

## Staged scalar expressions

| Family | Operations |
|---|---|
| literals/reads | Bool, String, Int, Nat literals; typed schema reads |
| control | typed `ifThenElse` |
| Bool | equality, and/or/not |
| String | append, equality |
| Int | add, subtract, multiply, comparisons, equality, Lean-compatible modulo, string conversion |
| Nat | add, clamped subtraction, multiply, comparisons, equality, zero-safe modulo, string conversion |
| dependent | checked `Vector` access by `Fin` |

Every listed scalar primitive has native/generated differential coverage.
JavaScript BigInt helpers preserve Lean's signed modulo, zero-divisor, and Nat
clamping behavior. The specialized Temperature backend separately lowers and
tests `Int.tdiv`; division is not a generic staged scalar primitive. Input
signatures are validated so one IR input index cannot be used at conflicting
runtime types.

## Static view vocabulary

The generic scalar component supports these closed tags:

- `main`, `header`, `footer`, `nav`, `aside`, `article`, and `section`;
- `div`, `p`, `span`, `h1`–`h6`, `strong`, `em`, `del`, `ul`, `ol`, and `li`;
- `a`, `blockquote`, `table`, `thead`, `tbody`, `tr`, `th`, `td`, `hr`, and `br`;
- `pre`, `code`, `button`, `form`, `input`, and `label`;
- static `class`, `id`, `aria-label`, checked `href`, and typed button `type`
  attributes;
- literal text and staged scalar text;
- click events on native buttons only.

No constructor exists for raw HTML, arbitrary tag/attribute/event names, style
text, images, generic key events, or direct DOM access. Link destinations cross
the `SafeHref` boundary, which rejects control characters, protocol-relative
URLs, and executable or unknown schemes.
Specialized checked form/region applications add only their documented typed
capabilities; they do not make arbitrary attributes public.

## Components and events

| Capability | Status |
|---|---|
| static source/derived graph | supported |
| source-setting scalar events | supported |
| nested batching | supported |
| affected-frontier scheduling and equality stop | supported |
| sink output cache / same-value DOM suppression | supported |
| derived reads during an event before a barrier | rejected (`LRX-TYPE-108`) |
| runtime dependency discovery | deliberately absent |
| arbitrary reducer extraction | unsupported; selected apps use checked specialized backends |

## Controlled forms

Typed adapters cover input value, checkbox checked, change/input, keydown payload
categories, prevented submit, disabled/checked properties, and the specific ARIA
error state needed by the dogfoods. Numeric validation uses an ASCII grammar
mirrored by the backend before BigInt conversion. Refined form commands have
private constructors and are revalidated at submit.

There is no general form/widget library or arbitrary DOM event object exposure.

## Dynamic shape

| Region | Behavior |
|---|---|
| conditional | replace one local branch and dispose the old branch |
| positional | reconcile fixed-position instances |
| keyed | preserve unique-key identity, move retained instances, dispose removed instances |
| delta-keyed | validate and apply insert/remove/move/update/reset batches before mutation |

The structural `ListDelta` planner is opt-in research. Filtering and sorting may
fall back to a visible reset. Delta is not the default language semantics.

## Effects and ports

| Boundary | Implemented contract |
|---|---|
| timer | owned, replaceable, cancelable, failure-delivering |
| storage | owned get/set, blocked getter normalized, visible errors |
| HTTP | owned `fetch`, query via `URLSearchParams`, abort replacement/disposal |
| foreign port | explicit typed metadata, synchronous/promise failures normalized |
| resource | loading/success/failure and stale token suppression |

Port decoders must validate untrusted wire data before state or keyed regions
mutate. Cancellation callbacks and browser/platform behavior remain trusted and
are adversarially tested.

## Output modes

- readable and compact validated ESM for scalar modules;
- application ESM plus exact adjacent manifest;
- graph JSON, DOT, and self-contained script-free HTML;
- editor-friendly `.generated.lean` aliases for selected applications;
- complete atomic versioned output bundles.

Generated ESM is standalone module text, not safe inline-script text. Generated
JSON is data, not safe HTML source. The documentation build keeps its boot shell
small and imports the module rather than interpolating generated text.

## Explicitly unsupported today

- arbitrary Lean-to-JavaScript compilation;
- arbitrary JavaScript escape hatches;
- general URL router/history integration (routing is the sealed
  one-per-component hash route table over the filter field, ADR-0063);
- general Virtual DOM or runtime dependency tracking;
- raw HTML, unrestricted URL attributes, CSS DSL, images, or broad element vocabulary;
- direct shadcn/ui component use or an installable Lean-native component registry;
- SSR or hydration;
- formal verification of the JavaScript engine, DOM, network, storage, or host;
- released package/versioning compatibility promise.

If a product requirement needs an unsupported item, the extension is more than
new syntax. It needs a closed typed representation, validation and diagnostics,
backend lowering, manifest/ABI disclosure, native and generated tests, hostile
boundary cases, cleanup behavior, and an ADR when a runtime contract changes.
The [architecture guide](architecture.md) describes that path in detail.
