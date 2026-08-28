import LeanRx

/-! Nest Lab dogfoods static child-component composition (ADR-0039), immutable
props across the mount ABI (ADR-0042), and the generic keyed region backend
(ADR-0041/0043/0044). The `<Pulse title="…"/>` element inside the `NestLab`
view resolves against the checked `Pulse_spec` in scope and lowers to a
`View.child` reference whose prop values ride the child's
`mount(target, props)` call, so the generated `NestLab.mjs` imports `mount`
from `./Pulse.mjs`, mounts the child in document order without a wrapper
element, and folds the child's disposer into its own. Composition is
transitive (ADR-0067): `Pulse` itself composes `<Tick label="…"/>` through
the same child table, so the generated `Pulse.mjs` imports `mount` from
`./Tick.mjs` and republishes the grandchild's mount return on its own
disposer's `children` array (ADR-0066), making the grandchild's
instrumentation reachable as `children[0].children[0]` from the root. The `roster` region is a
keyed list built entirely by the generic backend: `append roster (…)` pushes
rows with region-owned monotone keys, the sealed row template renders the
concatenation `{label ++ marks}` and selects the row class from the `marks`
field, the row `★` button mutates the dispatching row through the sealed
`mark` update action (one `updateAt` on commit), and the row `✕` button
removes it — resolved through structural delegated listeners on the `<ul>`
container. The per-row edit input dogfoods typed row payloads (ADR-0046):
`row roster rename (value : String) := set label value;` receives the
delegated `input` value and `row roster record (pressed : String) := …`
receives the delegated `keydown` key, each draining exactly one `updateAt`
on commit (`key` itself stays a reserved surface keyword).
Parent and child keep fully independent schemas, state, and events. -/

namespace LeanRxExamples.NestLab

open LeanRx

abbrev TickSchema : Schema := .field "ticks" Int .empty

def ticks : Field TickSchema Int := .here

open scoped LeanRxDsl

component Tick (schema := TickSchema) where {
  state ticks : Int := 0;
  prop label : String;
  event tick := set ticks (ticks + 1);
  view := jsx% <div class="tick"> [
    <h3 id="tick-label"> [{label}],
    <button type="button" onClick={tick}> ["Tick"],
    <p id="tick-text"> [{"tickText": rx% s!"Ticks: {ticks}"}]
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
    <Tick label="Tick child"/>
  ];
}

abbrev NestSchema : Schema := .field "clicks" Int (.field "added" Int .empty)

def clicks : Field NestSchema Int := .here

def added : Field NestSchema Int := .there .here

component NestLab (schema := NestSchema) where {
  state clicks : Int := 0;
  state added : Int := 0;
  event bump := set clicks (clicks + 1);
  event addItem := append roster (s!"Item {added}", "", "") then set added (added + 1);
  row roster mark := set marks (marks ++ " ★");
  row roster rename (value : String) := set label value;
  row roster record (pressed : String) := set lastKey ("key:" ++ pressed);
  region roster (label, marks, lastKey) := jsx%
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
      ]
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
