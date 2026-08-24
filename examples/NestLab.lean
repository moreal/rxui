import LeanRx

/-! Nest Lab dogfoods static child-component composition (ADR-0039): the
attr-less `<Pulse/>` element inside the `NestLab` view resolves against the
checked `Pulse_spec` in scope and lowers to a `View.child` reference, so the
generated `NestLab.mjs` imports `mount` from `./Pulse.mjs`, mounts the child in
document order without a wrapper element, and folds the child's disposer into
its own. Parent and child keep fully independent schemas, state, and events. -/

namespace LeanRxExamples.NestLab

open LeanRx

abbrev PulseSchema : Schema := .field "beats" Int .empty

def beats : Field PulseSchema Int := .here

open scoped LeanRxDsl

component Pulse (schema := PulseSchema) where {
  state beats : Int := 0;
  event pulse := set beats (beats + 1);
  view := jsx% <div class="pulse"> [
    <button type="button" onClick={pulse}> ["Pulse"],
    <p id="pulse-text"> [{"pulseText": rx% s!"Beats: {beats}"}]
  ];
}

abbrev NestSchema : Schema := .field "clicks" Int .empty

def clicks : Field NestSchema Int := .here

component NestLab (schema := NestSchema) where {
  state clicks : Int := 0;
  event bump := set clicks (clicks + 1);
  view := jsx% <main class="nest-lab"> [
    <h1> ["Nest Lab"],
    <button type="button" onClick={bump}> ["Bump"],
    <p id="nest-text"> [{"nestText": rx% s!"Clicks: {clicks}"}],
    <Pulse/>
  ];
}

end LeanRxExamples.NestLab
