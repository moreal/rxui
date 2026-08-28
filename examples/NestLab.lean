import LeanRx

/-! Nest Lab dogfoods static child-component composition (ADR-0039), immutable
props across the mount ABI (ADR-0042), and the generic keyed region backend
(ADR-0041/0043/0044). The `<Pulse title="…"/>` element inside the `NestLab`
view resolves against the checked `Pulse_spec` in scope and lowers to a
`View.child` reference whose prop values ride the child's
`mount(target, props)` call, so the generated `NestLab.mjs` imports `mount`
from `./Pulse.mjs`, mounts the child in document order without a wrapper
element, and folds the child's disposer into its own. Composition is
transitive (ADR-0067): `Pulse` itself composes `<Tick label={title}/>` through
the same child table, so the generated `Pulse.mjs` imports `mount` from
`./Tick.mjs` and republishes the grandchild's mount return on its own
disposer's `children` array (ADR-0066), making the grandchild's
instrumentation reachable as `children[0].children[0]` from the root. The
`label={title}` attribute forwards Pulse's own immutable `title` prop into
the grandchild's prop (ADR-0068): the value stays a mount-time constant, the
generated call reads the parent's positional mount argument —
`$lrx_child_0(node_0, [props[0]])` — and the grandchild therefore renders the
root-supplied literal two levels down. Re-forwarding is transitive
(ADR-0069): `Tick` forwards the `label` it received the same way into the
leaf `Blip` through `<Blip note={label}/>` — each level reads its own
positional prop, the forwarding rewrite never asks where the parent's value
came from, so the great-grandchild renders the root-supplied literal three
levels down and its instrumentation is reachable as
`children[0].children[0].children[0]`. Re-forwarding also fans out
(ADR-0070): `Tick` forwards the same received `label` into a second leaf
through `<Chip tag={label}/>`, so the child table, the aliased imports, and
the disposer's `children` array each scale by declaration order — both leaves
render the root-supplied literal and the sibling is reachable as
`children[0].children[0].children[1]`. Repeated composition of the same
child module is plain composition too (ADR-0071): `Tick` composes `Chip` a
second time through `<Chip tag="fixed chip"/>` — the child table stays
deduplicated by name (one aliased import), while every reference keeps its
own `ChildProp` list and its own `child_off_{n}`, so the forwarded and the
literal instance mount through one import with fully independent props and
state, the third instance is reachable as
`children[0].children[0].children[2]`, and the leaf template uses classes
(`.chip-tag`/`.chip-text`) rather than ids so two instances never collide
on a duplicate id. The `roster` region is a
keyed list built entirely by the generic backend: `append roster (…)` pushes
rows with region-owned monotone keys, the sealed row template renders the
concatenation `{label ++ marks}` and selects the row class from the `marks`
field, the row `★` button mutates the dispatching row through the sealed
`mark` update action (one `updateAt` on commit), and the row `✕` button
removes it — resolved through structural delegated listeners on the `<ul>`
container. The row template also composes one child per row (ADR-0075):
`<Chip tag={origin}/>` mounts a fourth `Chip` instance inside every mounted
row, its prop projecting the `origin` row field — a row-mount constant,
legal exactly because no row event or broadcast ever writes `origin` — and
its mount return is stashed on the row root, called by the generated row
dispose callback on every removal path, and republished through the live
`children` inventory the disposer shares with the region record: `children`
holds the static `Pulse` disposer first and then one entry per mounted row,
spliced as rows leave. The per-row edit input dogfoods typed row payloads (ADR-0046):
`row roster rename (value : String) := set label value;` receives the
delegated `input` value and `row roster record (pressed : String) := …`
receives the delegated `keydown` key, each draining exactly one `updateAt`
on commit (`key` itself stays a reserved surface keyword).
Parent and child keep fully independent schemas, state, and events. -/

namespace LeanRxExamples.NestLab

open LeanRx

abbrev BlipSchema : Schema := .field "blips" Int .empty

def blips : Field BlipSchema Int := .here

abbrev TickSchema : Schema := .field "ticks" Int .empty

def ticks : Field TickSchema Int := .here

open scoped LeanRxDsl

component Blip (schema := BlipSchema) where {
  state blips : Int := 0;
  prop note : String;
  event blip := set blips (blips + 1);
  view := jsx% <div class="blip"> [
    <span id="blip-note"> [{note}],
    <button type="button" onClick={blip}> ["Blip"],
    <p id="blip-text"> [{"blipText": rx% s!"Blips: {blips}"}]
  ];
}

abbrev ChipSchema : Schema := .field "chips" Int .empty

def chips : Field ChipSchema Int := .here

component Chip (schema := ChipSchema) where {
  state chips : Int := 0;
  prop tag : String;
  event chip := set chips (chips + 1);
  view := jsx% <div class="chip"> [
    <span class="chip-tag"> [{tag}],
    <button type="button" onClick={chip}> ["Chip"],
    <p class="chip-text"> [{"chipText": rx% s!"Chips: {chips}"}]
  ];
}

component Tick (schema := TickSchema) where {
  state ticks : Int := 0;
  prop label : String;
  event tick := set ticks (ticks + 1);
  view := jsx% <div class="tick"> [
    <h3 id="tick-label"> [{label}],
    <button type="button" onClick={tick}> ["Tick"],
    <p id="tick-text"> [{"tickText": rx% s!"Ticks: {ticks}"}],
    <Blip note={label}/>,
    <Chip tag={label}/>,
    <Chip tag="fixed chip"/>
  ];
}

abbrev PulseSchema : Schema := .field "beats" Int .empty

def beats : Field PulseSchema Int := .here

component Pulse (schema := PulseSchema) where {
  state beats : Int := 0;
  prop title : String;
  event pulse := set beats (beats + 1);
  view := jsx% <div class="pulse"> [
    <h2 id="pulse-title"> [{title}],
    <button type="button" onClick={pulse}> ["Pulse"],
    <p id="pulse-text"> [{"pulseText": rx% s!"Beats: {beats}"}],
    <Tick label={title}/>
  ];
}

abbrev NestSchema : Schema := .field "clicks" Int (.field "added" Int .empty)

def clicks : Field NestSchema Int := .here

def added : Field NestSchema Int := .there .here

component NestLab (schema := NestSchema) where {
  state clicks : Int := 0;
  state added : Int := 0;
  event bump := set clicks (clicks + 1);
  event addItem := append roster (s!"Item {added}", "", "", s!"Origin {added}")
    then set added (added + 1);
  row roster mark := set marks (marks ++ " ★");
  row roster rename (value : String) := set label value;
  row roster record (pressed : String) := set lastKey ("key:" ++ pressed);
  region roster (label, marks, lastKey, origin) := jsx%
    <li class={if marks == "" then "roster-row" else "roster-row marked"}> [
      <span class="roster-label"> [{label ++ marks}],
      <span class="roster-key"> [{lastKey}],
      <span class="roster-edit"> [
        <input ariaLabel="Rename row" onInput={rename} onKeyDown={record} />
      ],
      <span class="roster-mark"> [
        <button type="button" ariaLabel="Mark row" onClick={mark}> ["★"]
      ],
      <span class="roster-actions"> [
        <button type="button" ariaLabel="Remove row" onClick={remove}> ["✕"]
      ],
      <Chip tag={origin}/>
    ];
  view := jsx% <main class="nest-lab"> [
    <h1> ["Nest Lab"],
    <button type="button" onClick={bump}> ["Bump"],
    <p id="nest-text"> [{"nestText": rx% s!"Clicks: {clicks}"}],
    <button type="button" onClick={addItem}> ["Add item"],
    <ul id="roster" ariaLabel="Roster"> [<region roster/>],
    <Pulse title="Pulse child"/>
  ];
}

end LeanRxExamples.NestLab
