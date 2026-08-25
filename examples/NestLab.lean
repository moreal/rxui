import LeanRx

/-! Nest Lab dogfoods static child-component composition (ADR-0039), immutable
props across the mount ABI (ADR-0042), and the generic keyed region backend
(ADR-0041). The `<Pulse title="…"/>` element inside the `NestLab` view resolves
against the checked `Pulse_spec` in scope and lowers to a `View.child`
reference whose prop values ride the child's `mount(target, props)` call, so
the generated `NestLab.mjs` imports `mount` from `./Pulse.mjs`, mounts the
child in document order without a wrapper element, and folds the child's
disposer into its own. The `roster` region is a keyed list built entirely by
the generic backend: `append roster (…)` pushes rows with region-owned
monotone keys, the sealed row template projects the `label` field, and the row
`✕` button resolves through one structural delegated listener on the `<ul>`
container. Parent and child keep fully independent schemas, state, and
events. -/

namespace LeanRxExamples.NestLab

open LeanRx

abbrev PulseSchema : Schema := .field "beats" Int .empty

def beats : Field PulseSchema Int := .here

open scoped LeanRxDsl

component Pulse (schema := PulseSchema) where {
  state beats : Int := 0;
  prop title : String;
  event pulse := set beats (beats + 1);
  view := jsx% <div class="pulse"> [
    <h2 id="pulse-title"> [{title}],
    <button type="button" onClick={pulse}> ["Pulse"],
    <p id="pulse-text"> [{"pulseText": rx% s!"Beats: {beats}"}]
  ];
}

abbrev NestSchema : Schema := .field "clicks" Int (.field "added" Int .empty)

def clicks : Field NestSchema Int := .here

def added : Field NestSchema Int := .there .here

component NestLab (schema := NestSchema) where {
  state clicks : Int := 0;
  state added : Int := 0;
  event bump := set clicks (clicks + 1);
  event addItem := append roster (s!"Item {added}") then set added (added + 1);
  region roster (label) := jsx% <li class="roster-row"> [
    <span class="roster-label"> [{label}],
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
