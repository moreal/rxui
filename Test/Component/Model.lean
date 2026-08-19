import examples.Counter

namespace LeanRxTest.Component.Model

open LeanRx LeanRxExamples.Counter

private def expectError (code : String)
    (result : Except ComponentError (CheckedComponent Γ)) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"expected component error {code}"
  | .error error =>
      unless error.code == code do
        throw <| IO.userError s!"expected {code}, got {error.code}"

private def checkCounter (checked : CheckedComponent CounterSchema) : IO Unit := do
  unless checked.sourceCount == 1 do
    throw <| IO.userError "Counter source prefix changed"
  unless checked.graph.graph.nodes.map (·.name) ==
      #["count", "doubled", "parity", "countText", "doubledText", "parityText"] do
    throw <| IO.userError "component graph did not derive stable value/sink nodes"
  unless checked.graph.graph.nodes.map (·.rank) == #[0, 1, 1, 1, 2, 2] do
    throw <| IO.userError "component graph ranks changed"

def run : IO Unit := do
  match spec.check with
  | .error error => throw <| IO.userError s!"Counter spec rejected: {error.code}"
  | .ok checked => checkCounter checked
  let writesDerived : ComponentSpec CounterSchema :=
    { spec with events := #[{
        name := "bad"
        update := .set doubledField (RxExpr.literal (.int 9))
      }] }
  expectError "LRX-TYPE-107" writesDerived.check
  let readsDerived : ComponentSpec CounterSchema :=
    { spec with events := #[{
        name := "badRead"
        update := .set count (RxExpr.binary .intAdd
          (RxExpr.read doubledField) (RxExpr.literal (.int 1)))
      }] }
  expectError "LRX-TYPE-108" readsDerived.check
  let unknownEvent : ComponentSpec CounterSchema :=
    { spec with view := (View.node .button [.text "Bad"]
        (events := [{ kind := .click, eventName := "missing" }])) }
  expectError "LRX-VIEW-006" unknownEvent.check
  let duplicateAttr : ComponentSpec CounterSchema :=
    { spec with view := (View.node .p [.text "Bad"]
        (attrs := [.className "a", .className "b"])) }
  expectError "LRX-VIEW-001" duplicateAttr.check
  let invalidButtonAttr : ComponentSpec CounterSchema :=
    { spec with view := (View.node .p [.text "Bad"] (attrs := [.buttonType .button])) }
  expectError "LRX-VIEW-003" invalidButtonAttr.check
  let clickDiv : ComponentSpec CounterSchema :=
    { spec with view := (View.node .div [.text "Bad"]
        (events := [{ kind := .click, eventName := "increment" }])) }
  expectError "LRX-VIEW-005" clickDiv.check
  let mismatchedSurface : ComponentSpec CounterSchema :=
    { spec with surface := #[
        { role := .derived, name := "count", span := .generated },
        { role := .derived, name := "doubled", span := .generated },
        { role := .derived, name := "parity", span := .generated },
        { role := .event, name := "increment", span := .generated },
        { role := .event, name := "addTwo", span := .generated }
      ] }
  expectError "LRX-ELAB-103" mismatchedSurface.check
  let cycle : ComponentSpec (.field "a" Int <| .field "b" Int .empty) :=
    { name := "Cycle"
      values := #[
        ValueSpec.computed (.here : Field (.field "a" Int <| .field "b" Int .empty) Int)
          (RxExpr.read (.there .here)),
        ValueSpec.computed (.there .here : Field (.field "a" Int <| .field "b" Int .empty) Int)
          (RxExpr.read .here)
      ]
      events := #[]
      view := View.node .p [.text "cycle"] }
  expectError "LRX-GRAPH-001" cycle.check

end LeanRxTest.Component.Model
