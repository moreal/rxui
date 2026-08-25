import LeanRx

namespace LeanRxTest.Docs.LanguageGuide

open LeanRx

abbrev CounterSchema : Schema :=
  .field "count" Int <| .field "label" String .empty

def count : Field CounterSchema Int := .here
def label : Field CounterSchema String := .there .here

def doubled := RxExpr.binary .intMul
  (RxExpr.read count)
  (RxExpr.literal (.int 2))

def countText := RxExpr.binary .stringAppend
  (RxExpr.literal (.string "Count: "))
  (RxExpr.unary .intToString (RxExpr.read count))

def values : Array (ValueSpec CounterSchema) := #[
  ValueSpec.state count (.int 1),
  ValueSpec.computed label countText
]

def increment : EventSpec CounterSchema :=
  { name := "increment"
    update := .set count <| RxExpr.binary .intAdd
      (RxExpr.read count) (RxExpr.literal (.int 1)) }

def counterView : View CounterSchema := View.node .main [
  View.node .h1 [.text "Counter"],
  View.node .button [.text "Increment"]
    (attrs := [.buttonType .button])
    (events := [{ kind := .click, eventName := "increment" }]),
  View.node .p [.scalarText "countText" countText]
]

def spec : ComponentSpec CounterSchema :=
  { name := "Counter"
    values
    events := #[increment]
    view := counterView }

def checked := spec.check

open scoped LeanRxDsl

component CounterSyntax (schema := CounterSchema) where {
  state count : Int := 1;
  derived label := rx% s!"Count: {count}";
  event increment := set count (count + 1);
  view := jsx% <main> [
    <h1> ["Counter"],
    <button type="button" onClick={increment}> ["Increment"],
    <p> [{"countText": rx% s!"Count: {count}"}]
  ];
}

/- The explicit right-hand sides remain valid alongside the sugared items. -/
component CounterExplicitSyntax (schema := CounterSchema) where {
  state count := ValueSpec.state count (.int 1);
  derived label := ValueSpec.computed label countText;
  event increment := increment;
  view := counterView;
}

/- The controlled-input snippet from guide section 7 (ADR-0038). -/
abbrev EchoMiniSchema : Schema :=
  .field "draft" String <| .field "loud" Bool .empty

def draft : Field EchoMiniSchema String := .here
def loud : Field EchoMiniSchema Bool := .there .here

component EchoMini (schema := EchoMiniSchema) where {
  state draft : String := "";
  state loud : Bool := false;
  event save := set draft "";
  event setDraft (value : String) := set draft value;
  event toggleLoud (checked : Bool) := set loud checked;
  view := jsx% <main> [
    <form onSubmit={save}> [
      <input ariaLabel="Draft" value={rx% draft} onInput={setDraft} />,
      <input ariaLabel="Loud" type="checkbox" checked={rx% loud} onCheckedChange={toggleLoud} />,
      <button type="submit"> ["Save"]
    ]
  ];
}

/- The static child-nesting snippet from guide section 7 (ADR-0039). -/
abbrev NestMiniSchema : Schema := .field "clicks" Int .empty

def clicks : Field NestMiniSchema Int := .here

component NestMini (schema := NestMiniSchema) where {
  state clicks : Int := 0;
  event bump := set clicks (clicks + 1);
  view := jsx% <main> [
    <button type="button" onClick={bump}> ["Bump"],
    <EchoMini/>
  ];
}

/- The keyed region snippet from guide section 7 (ADR-0040/0041). -/
abbrev RosterMiniSchema : Schema := .field "added" Int .empty

def added : Field RosterMiniSchema Int := .here

component RosterMini (schema := RosterMiniSchema) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}") then set added (added + 1);
  region roster (label) := jsx% <li> [
    <span> [{label}],
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}

/- The immutable-prop snippets from guide section 7 (ADR-0042). -/
abbrev TitledMiniSchema : Schema := .field "titledClicks" Int .empty

def titledClicks : Field TitledMiniSchema Int := .here

component TitledMini (schema := TitledMiniSchema) where {
  state titledClicks : Int := 0;
  prop title : String;
  event bump := set titledClicks (titledClicks + 1);
  view := jsx% <main> [
    <h1> [{title}],
    <button type="button" onClick={bump}> ["Bump"]
  ];
}

abbrev PropNestMiniSchema : Schema := .field "hosts" Int .empty

def hosts : Field PropNestMiniSchema Int := .here

component PropNestMini (schema := PropNestMiniSchema) where {
  state hosts : Int := 0;
  event host := set hosts (hosts + 1);
  view := jsx% <main> [
    <button type="button" onClick={host}> ["Host"],
    <TitledMini title="Hello"/>
  ];
}

def run : IO Unit := do
  unless doubled.dependencies.ids == [0] && countText.dependencies.ids == [0] do
    throw <| IO.userError "language-guide expression dependencies changed"
  match checked, CounterSyntax_check with
  | .ok explicit, .ok generated =>
      unless explicit.graph.graph.nodes.map (·.name) ==
          generated.graph.graph.nodes.map (·.name) do
        throw <| IO.userError "language-guide explicit and scoped graphs diverged"
  | .error error, _ | _, .error error =>
      throw <| IO.userError s!"language-guide component rejected: {error.render}"
  match CounterExplicitSyntax_check with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError s!"language-guide explicit component rejected: {error.render}"
  match EchoMini_check with
  | .ok controlled =>
      unless controlled.view.props.map (·.binding.name) == ["value", "checked"] do
        throw <| IO.userError "language-guide controlled snippet lost its reflections"
  | .error error =>
      throw <| IO.userError s!"language-guide controlled component rejected: {error.render}"
  match NestMini_check with
  | .ok nested =>
      unless nested.spec.children.toList.map (·.name) == ["EchoMini"] do
        throw <| IO.userError "language-guide nesting snippet lost its child table"
  | .error error =>
      throw <| IO.userError s!"language-guide nested component rejected: {error.render}"
  match RosterMini_check with
  | .ok roster =>
      unless roster.spec.regions.toList.map (·.name) == ["roster"] &&
          roster.view.regionRefs.map (·.name) == ["roster"] do
        throw <| IO.userError "language-guide region snippet lost its region table"
  | .error error =>
      throw <| IO.userError s!"language-guide region component rejected: {error.render}"
  match TitledMini_check, PropNestMini_check with
  | .ok titled, .ok host =>
      unless titled.spec.propNames == ["title"] &&
          host.view.childRefs.map (·.props) == [[("title", "Hello")]] do
        throw <| IO.userError "language-guide prop snippets lost their bindings"
  | .error error, _ | _, .error error =>
      throw <| IO.userError s!"language-guide prop component rejected: {error.render}"

end LeanRxTest.Docs.LanguageGuide
