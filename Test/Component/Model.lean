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
      #["count", "doubled", "parity", "countText", "doubledText", "parityText",
        "stableText", "hostileText"] do
    throw <| IO.userError "component graph did not derive stable value/sink nodes"
  unless checked.graph.graph.nodes.map (·.rank) == #[0, 1, 1, 1, 2, 2, 1, 0] do
    throw <| IO.userError "component graph ranks changed"
  let nested ← match checked.eventSummaries.toList.find? (·.name == "nestedAddTwo") with
    | some summary => pure summary
    | none => throw <| IO.userError "nested event summary disappeared"
  unless nested.directWrites.isEmpty && nested.directReads.isEmpty &&
      nested.dispatchedEvents == ["increment"] && nested.effectiveWrites == [0] &&
      nested.effectiveReads == [0] do
    throw <| IO.userError "nested event transitive read/write summary changed"

def run : IO Unit := do
  match spec.check with
  | .error error => throw <| IO.userError s!"Counter spec rejected: {error.code}"
  | .ok checked => checkCounter checked
  let writesDerived : ComponentSpec CounterSchema :=
    { spec with events := #[{
        name := "bad"
        update := .set doubled (RxExpr.literal (.int 9))
      }] }
  expectError "LRX-TYPE-107" writesDerived.check
  let readsDerived : ComponentSpec CounterSchema :=
    { spec with events := #[{
        name := "badRead"
        update := .set count (RxExpr.binary .intAdd
          (RxExpr.read doubled) (RxExpr.literal (.int 1)))
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
  let unknownDispatch : ComponentSpec CounterSchema :=
    { spec with events := #[{
        name := "badDispatch"
        update := .dispatch "missing"
      }] }
  expectError "LRX-ELAB-106" unknownDispatch.check
  let mismatchedSurface : ComponentSpec CounterSchema :=
    { spec with surface := #[
        { role := .derived, name := "count", span := .generated },
        { role := .derived, name := "doubled", span := .generated },
        { role := .derived, name := "parity", span := .generated },
        { role := .event, name := "increment", span := .generated },
        { role := .event, name := "addTwo", span := .generated },
        { role := .event, name := "nestedAddTwo", span := .generated },
        { role := .event, name := "roundTrip", span := .generated }
      ] }
  expectError "LRX-ELAB-103" mismatchedSurface.check
  let undeclaredChild : ComponentSpec CounterSchema :=
    { spec with view := View.node .main [View.child "Ghost"] }
  expectError "LRX-VIEW-023" undeclaredChild.check
  let badSpecifier : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [View.child "Ghost"]
        children := #[{ name := "Ghost", moduleSpecifier := "../Ghost.mjs" }] }
  expectError "LRX-VIEW-024" badSpecifier.check
  let duplicateProps : ComponentSpec CounterSchema :=
    { spec with view := (View.node .input []
        (props := [.value countText, .value doubledText])) }
  expectError "LRX-VIEW-021" duplicateProps.check
  let reflectOnButton : ComponentSpec CounterSchema :=
    { spec with view := (View.node .button [.text "Bad"]
        (props := [.value countText])) }
  expectError "LRX-VIEW-020" reflectOnButton.check
  let rowTemplate : RowNode := RowNode.node .li [
    RowNode.node .span [RowNode.fieldText 0],
    RowNode.node .span [RowNode.node .button [RowNode.text "x"]
      (attrs := [.buttonType .button])
      (events := [{ kind := .click, eventName := "remove" }])]
  ]
  let rosterRegion : RegionSpec := {
    name := "r"
    fields := #["label"]
    template := rowTemplate
    events := #[{ name := "remove", action := .remove }]
  }
  let regionView : View CounterSchema := View.node .main [View.node .ul [View.region "r"]]
  let goodRegion : ComponentSpec CounterSchema :=
    { spec with view := regionView, regions := #[rosterRegion] }
  match goodRegion.check with
  | .error error =>
      throw <| IO.userError s!"forged keyed region rejected: {error.code}"
  | .ok checked =>
      unless checked.view.regionRefs.map (·.path) == [[0, 0]] do
        throw <| IO.userError "forged keyed region lost its mounted slot"
  let unknownRegion : ComponentSpec CounterSchema :=
    { spec with view := regionView }
  expectError "LRX-VIEW-025" unknownRegion.check
  let unmountedRegion : ComponentSpec CounterSchema :=
    { spec with regions := #[rosterRegion] }
  expectError "LRX-VIEW-025" unmountedRegion.check
  let outOfBoundsField : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.fieldText 1] }] }
  expectError "LRX-VIEW-026" outOfBoundsField.check
  let buttonAsCell : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.node .button [RowNode.text "x"]
          (attrs := [.buttonType .button])
          (events := [{ kind := .click, eventName := "remove" }])] }] }
  expectError "LRX-VIEW-027" buttonAsCell.check
  let unknownRowEvent : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with events := #[] }] }
  expectError "LRX-VIEW-028" unknownRowEvent.check
  let regionWithSibling : ComponentSpec CounterSchema :=
    { goodRegion with view := View.node .main [
        View.node .ul [View.region "r", View.text "sibling"]] }
  expectError "LRX-VIEW-029" regionWithSibling.check
  let appendUnknownRegion : ComponentSpec CounterSchema :=
    { goodRegion with events := #[{
        name := "badAppend"
        update := .regionAppend "ghost" [RowValue.of (RxExpr.literal (.string "x"))]
      }] }
  expectError "LRX-TYPE-109" appendUnknownRegion.check
  let appendWrongArity : ComponentSpec CounterSchema :=
    { goodRegion with events := #[{
        name := "fatAppend"
        update := .regionAppend "r" [
          RowValue.of (RxExpr.literal (.string "x")),
          RowValue.of (RxExpr.literal (.string "y"))
        ]
      }] }
  expectError "LRX-TYPE-110" appendWrongArity.check
  /- ADR-0043 row update actions and row expressions, ADR-0044 class
  selections, exercised through forged specifications. -/
  let markEvent : RowEventSpec :=
    { name := "mark", action := .update [(0, .append (.field 0) (.lit "!"))] }
  let updatingTemplate : RowNode := RowNode.node .li [
    RowNode.node .span [RowNode.exprText (.append (.field 0) (.lit "?"))],
    RowNode.node .span [RowNode.node .button [RowNode.text "m"]
      (attrs := [.buttonType .button])
      (events := [{ kind := .click, eventName := "mark" }])]
  ] (classIf := [{ field := 0, equals := "", whenTrue := "a", whenFalse := "b" }])
  let updatingRegion : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := updatingTemplate
        events := #[{ name := "remove", action := .remove }, markEvent] }] }
  match updatingRegion.check with
  | .error error =>
      throw <| IO.userError s!"forged updating region rejected: {error.code}"
  | .ok _ => pure ()
  let emptyUpdate : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        events := #[{ name := "remove", action := .remove },
          { name := "noop", action := .update [] }] }] }
  expectError "LRX-VIEW-031" emptyUpdate.check
  let duplicateUpdateTarget : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        events := #[{ name := "remove", action := .remove },
          { name := "twice", action := .update [(0, .lit "x"), (0, .lit "y")] }] }] }
  expectError "LRX-VIEW-031" duplicateUpdateTarget.check
  let updateTargetOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        events := #[{ name := "remove", action := .remove },
          { name := "far", action := .update [(1, .lit "x")] }] }] }
  expectError "LRX-VIEW-031" updateTargetOutOfBounds.check
  let updateReadOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        events := #[{ name := "remove", action := .remove },
          { name := "deep", action := .update [(0, .field 1)] }] }] }
  expectError "LRX-VIEW-031" updateReadOutOfBounds.check
  let exprTextOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.exprText (.field 1)] }] }
  expectError "LRX-VIEW-026" exprTextOutOfBounds.check
  let classSelectOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.fieldText 0]
          (classIf := [{ field := 1, equals := "", whenTrue := "a", whenFalse := "b" }]) }] }
  expectError "LRX-VIEW-026" classSelectOutOfBounds.check
  let classSelectBesideClass : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.fieldText 0]
          (attrs := [.className "static"])
          (classIf := [{ field := 0, equals := "", whenTrue := "a", whenFalse := "b" }]) }] }
  expectError "LRX-VIEW-001" classSelectBesideClass.check
  let danglingPropText : ComponentSpec CounterSchema :=
    { spec with view := View.node .p [View.propText 0] }
  expectError "LRX-VIEW-030" danglingPropText.check
  let duplicatePropNames : ComponentSpec CounterSchema :=
    { spec with props := #[{ name := "t" }, { name := "t" }] }
  expectError "LRX-VIEW-030" duplicatePropNames.check
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
