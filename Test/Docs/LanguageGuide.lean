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

end LeanRxTest.Docs.LanguageGuide
