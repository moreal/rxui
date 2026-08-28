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
    { name := "mark", action := .update ⟨[(0, .append (.field 0) (.lit "!"))], none⟩ }
  let updatingTemplate : RowNode := RowNode.node .li [
    RowNode.node .span [RowNode.exprText (.append (.field 0) (.lit "?"))],
    RowNode.node .span [RowNode.node .button [RowNode.text "m"]
      (attrs := [.buttonType .button])
      (events := [{ kind := .click, eventName := "mark" }])]
  ] (classIf := [{ predicate := .ofField 0 "", whenTrue := "a", whenFalse := "b" }])
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
          { name := "noop", action := .update ⟨[], none⟩ }] }] }
  expectError "LRX-VIEW-031" emptyUpdate.check
  let duplicateUpdateTarget : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        events := #[{ name := "remove", action := .remove },
          { name := "twice", action := .update ⟨[(0, .lit "x"), (0, .lit "y")], none⟩ }] }] }
  expectError "LRX-VIEW-031" duplicateUpdateTarget.check
  let updateTargetOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        events := #[{ name := "remove", action := .remove },
          { name := "far", action := .update ⟨[(1, .lit "x")], none⟩ }] }] }
  expectError "LRX-VIEW-031" updateTargetOutOfBounds.check
  let updateReadOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        events := #[{ name := "remove", action := .remove },
          { name := "deep", action := .update ⟨[(0, .field 1)], none⟩ }] }] }
  expectError "LRX-VIEW-031" updateReadOutOfBounds.check
  let exprTextOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.exprText (.field 1)] }] }
  expectError "LRX-VIEW-026" exprTextOutOfBounds.check
  let classSelectOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.fieldText 0]
          (classIf := [{ predicate := .ofField 1 "", whenTrue := "a", whenFalse := "b" }]) }] }
  expectError "LRX-VIEW-026" classSelectOutOfBounds.check
  let classSelectBesideClass : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.fieldText 0]
          (attrs := [.className "static"])
          (classIf := [{ predicate := .ofField 0 "", whenTrue := "a", whenFalse := "b" }]) }] }
  expectError "LRX-VIEW-001" classSelectBesideClass.check
  /- ADR-0045 state-scoped attribute selections, exercised through forged
  specifications against the typed `parity` field. -/
  let selectingButton : ComponentSpec CounterSchema :=
    { spec with view := View.node .main [View.node .button [.text "Even"]
        (attrs := [.buttonType .button])
        (events := [{ kind := .click, eventName := "increment" }])
        (selects := [.classSelect parity "even" "selected" "",
          .pressedSelect parity "even", .disabledSelect parity "even"])] }
  match selectingButton.check with
  | .error error =>
      throw <| IO.userError s!"forged attribute selection rejected: {error.code}"
  | .ok checked =>
      unless checked.view.attrSelects.map
          (fun mounted => (mounted.select.name, mounted.path)) ==
          [("class", [0]), ("aria-pressed", [0]), ("disabled", [0])] do
        throw <| IO.userError "forged attribute selection lost its mounted positions"
      unless (checked.graph.graph.nodes.map (·.name)).toList.drop 3 ==
          ["attr:0:class", "attr:1:aria-pressed", "attr:2:disabled"] do
        throw <| IO.userError "forged attribute selection lost its graph sinks"
  let pressedOnParagraph : ComponentSpec CounterSchema :=
    { spec with view := (View.node .p [.text "Bad"]
        (selects := [.pressedSelect parity "even"])) }
  expectError "LRX-VIEW-032" pressedOnParagraph.check
  let disabledOnParagraph : ComponentSpec CounterSchema :=
    { spec with view := (View.node .p [.text "Bad"]
        (selects := [.disabledSelect parity "even"])) }
  expectError "LRX-VIEW-032" disabledOnParagraph.check
  let selectBesideStaticClass : ComponentSpec CounterSchema :=
    { spec with view := (View.node .p [.text "Bad"]
        (attrs := [.className "static"])
        (selects := [.classSelect parity "even" "a" "b"])) }
  expectError "LRX-VIEW-001" selectBesideStaticClass.check
  let doubleClassSelect : ComponentSpec CounterSchema :=
    { spec with view := (View.node .p [.text "Bad"]
        (selects := [.classSelect parity "even" "a" "b",
          .classSelect parity "odd" "c" "d"])) }
  expectError "LRX-VIEW-001" doubleClassSelect.check
  /- ADR-0057 trimmed selection subjects: the sealed trim unary in front of
  the selection field rides every existing selection obligation — same
  duplicate detection, same native-button rule, same graph sinks — with the
  trimmed flag surfacing in the debug marker. -/
  let trimmedSelectingButton : ComponentSpec CounterSchema :=
    { spec with view := View.node .main [View.node .button [.text "Even"]
        (attrs := [.buttonType .button])
        (events := [{ kind := .click, eventName := "increment" }])
        (selects := [.classSelect parity "even" "selected" "" (trimmed := true),
          .pressedSelect parity "even" (trimmed := true),
          .disabledSelect parity "even" (trimmed := true)])] }
  match trimmedSelectingButton.check with
  | .error error =>
      throw <| IO.userError s!"forged trimmed attribute selection rejected: {error.code}"
  | .ok checked =>
      unless checked.view.attrSelects.map
          (fun mounted => (mounted.select.name, mounted.select.trimmed)) ==
          [("class", true), ("aria-pressed", true), ("disabled", true)] do
        throw <| IO.userError "forged trimmed attribute selection lost its trim flags"
      unless checked.view.attrSelects.map (·.select.debug) ==
          ["select:class:trim:2", "select:aria-pressed:trim:2",
            "select:disabled:trim:2"] do
        throw <| IO.userError "forged trimmed attribute selection lost its debug markers"
      unless (checked.graph.graph.nodes.map (·.name)).toList.drop 3 ==
          ["attr:0:class", "attr:1:aria-pressed", "attr:2:disabled"] do
        throw <| IO.userError "forged trimmed attribute selection lost its graph sinks"
  let trimmedPressedOnParagraph : ComponentSpec CounterSchema :=
    { spec with view := (View.node .p [.text "Bad"]
        (selects := [.pressedSelect parity "even" (trimmed := true)])) }
  expectError "LRX-VIEW-032" trimmedPressedOnParagraph.check
  /- ADR-0058 empty-region visibility: the sealed region-subject `hidden`
  selection is accepted on the region's wrapper with the boolean value type
  and its own debug marker, and — like the ADR-0050 count texts — it is
  region-driven: no planned-graph sink and no state refs. An unknown region
  is rejected, and a second hidden selection duplicates the attribute. -/
  let hidingWrapper : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [View.node .ul [View.region "r"]
          (selects := [.hiddenIfEmpty "r"])]
        regions := #[rosterRegion] }
  match hidingWrapper.check with
  | .error error =>
      throw <| IO.userError s!"forged hidden reflection rejected: {error.code}"
  | .ok checked =>
      unless checked.view.attrSelects.map (fun mounted =>
          (mounted.select.name, mounted.select.hiddenRegion?,
            mounted.select.fieldIndex?, mounted.path)) ==
          [("hidden", some "r", none, [0])] do
        throw <| IO.userError "forged hidden reflection lost its mounted selection"
      unless checked.view.attrSelects.map
          (fun mounted => (mounted.select.debug, mounted.select.valueType)) ==
          [("select:hidden:r", .bool)] do
        throw <| IO.userError "forged hidden reflection lost its debug marker"
      unless (checked.graph.graph.nodes.map (·.name)).toList.all
          (fun name => !name.startsWith "attr:") do
        throw <| IO.userError "forged hidden reflection leaked into the planned graph"
  let hidingUnknownRegion : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [View.node .ul [View.region "r"]
          (selects := [.hiddenIfEmpty "s"])]
        regions := #[rosterRegion] }
  expectError "LRX-VIEW-042" hidingUnknownRegion.check
  let doubleHidden : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [View.node .ul [View.region "r"]
          (selects := [.hiddenIfEmpty "r", .hiddenIfEmpty "r"])]
        regions := #[rosterRegion] }
  expectError "LRX-VIEW-001" doubleHidden.check
  /- ADR-0059 predicate-count visibility: the sealed predicate-count subject
  is accepted with its own debug marker and the same boolean value type,
  graph exclusion, and region subject; an out-of-bounds predicate field is
  rejected with the ADR-0050 count-predicate rule. -/
  let hidingPredicate : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [View.node .button [View.text "Clear"]
            (selects := [.hiddenIfEmpty "r" (predicate := some (0, "true"))]),
          View.node .ul [View.region "r"]]
        regions := #[rosterRegion] }
  match hidingPredicate.check with
  | .error error =>
      throw <| IO.userError s!"forged predicate hidden reflection rejected: {error.code}"
  | .ok checked =>
      unless checked.view.attrSelects.map (fun mounted =>
          (mounted.select.name, mounted.select.hiddenRegion?,
            mounted.select.hiddenPredicate?, mounted.select.fieldIndex?,
            mounted.path)) ==
          [("hidden", some "r", some (0, "true"), none, [0])] do
        throw <| IO.userError
          "forged predicate hidden reflection lost its mounted selection"
      unless checked.view.attrSelects.map
          (fun mounted => (mounted.select.debug, mounted.select.valueType)) ==
          [("select:hidden:r:0:true", .bool)] do
        throw <| IO.userError
          "forged predicate hidden reflection lost its debug marker"
      unless (checked.graph.graph.nodes.map (·.name)).toList.all
          (fun name => !name.startsWith "attr:") do
        throw <| IO.userError
          "forged predicate hidden reflection leaked into the planned graph"
  let hidingPredicateOutOfBounds : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [View.node .ul [View.region "r"]
          (selects := [.hiddenIfEmpty "r" (predicate := some (1, "true"))])]
        regions := #[rosterRegion] }
  expectError "LRX-VIEW-042" hidingPredicateOutOfBounds.check
  /- ADR-0060 toggle-all checked reflection: the sealed region-count subject
  is accepted as the `checked` property of a static type="checkbox" input —
  total or predicate form, each with its own debug marker, the boolean
  value type, and the same graph exclusion — and demands the checkbox: any
  other element is rejected. The unknown-region and out-of-bounds rules
  ride LRX-VIEW-042, a selection beside a controlled `checked` binding
  duplicates the reflected property, and the payload-less change binding
  is likewise accepted only from a checkbox input. -/
  let toggleAllBox : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [
          View.node .input [] (attrs := [.inputType .checkbox])
            (selects := [.checkedIfEmpty "r" (predicate := some (0, "x"))]),
          View.node .ul [View.region "r"]]
        regions := #[rosterRegion] }
  match toggleAllBox.check with
  | .error error =>
      throw <| IO.userError s!"forged checked reflection rejected: {error.code}"
  | .ok checked =>
      unless checked.view.attrSelects.map (fun mounted =>
          (mounted.select.name, mounted.select.checkedRegion?,
            mounted.select.checkedPredicate?, mounted.select.regionSubject?,
            mounted.select.fieldIndex?, mounted.path)) ==
          [("checked", some "r", some (0, "x"), some "r", none, [0])] do
        throw <| IO.userError "forged checked reflection lost its mounted selection"
      unless checked.view.attrSelects.map
          (fun mounted => (mounted.select.debug, mounted.select.valueType)) ==
          [("select:checked:r:0:x", .bool)] do
        throw <| IO.userError "forged checked reflection lost its debug marker"
      unless (checked.graph.graph.nodes.map (·.name)).toList.all
          (fun name => !name.startsWith "attr:") do
        throw <| IO.userError "forged checked reflection leaked into the planned graph"
  let totalCheckedBox : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [
          View.node .input [] (attrs := [.inputType .checkbox])
            (selects := [.checkedIfEmpty "r"]),
          View.node .ul [View.region "r"]]
        regions := #[rosterRegion] }
  match totalCheckedBox.check with
  | .error error =>
      throw <| IO.userError s!"forged total checked reflection rejected: {error.code}"
  | .ok checked =>
      unless checked.view.attrSelects.map
          (fun mounted => (mounted.select.debug, mounted.select.checkedPredicate?)) ==
          [("select:checked:r", none)] do
        throw <| IO.userError "forged total checked reflection lost its debug marker"
  let checkedUnknownRegion : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [
          View.node .input [] (attrs := [.inputType .checkbox])
            (selects := [.checkedIfEmpty "s"]),
          View.node .ul [View.region "r"]]
        regions := #[rosterRegion] }
  expectError "LRX-VIEW-042" checkedUnknownRegion.check
  let checkedOutOfBounds : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [
          View.node .input [] (attrs := [.inputType .checkbox])
            (selects := [.checkedIfEmpty "r" (predicate := some (1, "x"))]),
          View.node .ul [View.region "r"]]
        regions := #[rosterRegion] }
  expectError "LRX-VIEW-042" checkedOutOfBounds.check
  let checkedOnButton : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [
          View.node .button [.text "Bad"] (attrs := [.buttonType .button])
            (selects := [.checkedIfEmpty "r"]),
          View.node .ul [View.region "r"]]
        regions := #[rosterRegion] }
  expectError "LRX-VIEW-043" checkedOnButton.check
  let checkedOnTextInput : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [
          View.node .input [] (attrs := [.inputType .text])
            (selects := [.checkedIfEmpty "r"]),
          View.node .ul [View.region "r"]]
        regions := #[rosterRegion] }
  expectError "LRX-VIEW-043" checkedOnTextInput.check
  let checkedBesideControlled : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [
          View.node .input [] (attrs := [.inputType .checkbox])
            (props := [.checked (RxExpr.literal (.bool true))])
            (selects := [.checkedIfEmpty "r"]),
          View.node .ul [View.region "r"]]
        regions := #[rosterRegion] }
  expectError "LRX-VIEW-021" checkedBesideControlled.check
  let plainChangeOnCheckbox : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [
          View.node .input [] (attrs := [.inputType .checkbox])
            (events := [{ kind := .change, eventName := "increment" }]),
          View.node .ul [View.region "r"]]
        regions := #[rosterRegion] }
  match plainChangeOnCheckbox.check with
  | .error error =>
      throw <| IO.userError s!"forged payload-less change binding rejected: {error.code}"
  | .ok checked =>
      unless checked.view.events.map (fun mounted =>
          (mounted.binding.kind, mounted.binding.eventName, mounted.path)) ==
          [(.change, "increment", [0])] do
        throw <| IO.userError "forged payload-less change binding lost its mount"
  let plainChangeOnTextInput : ComponentSpec CounterSchema :=
    { spec with
        view := View.node .main [
          View.node .input [] (attrs := [.inputType .text])
            (events := [{ kind := .change, eventName := "increment" }]),
          View.node .ul [View.region "r"]]
        regions := #[rosterRegion] }
  expectError "LRX-VIEW-043" plainChangeOnTextInput.check
  /- ADR-0046 typed row payloads, exercised through forged specifications. -/
  let renameEvent : RowEventSpec :=
    { name := "rename", action := .update ⟨[(0, .payload)], none⟩, takesPayload := true }
  let typedTemplate : RowNode := RowNode.node .li [
    RowNode.node .span [RowNode.fieldText 0],
    RowNode.node .span [RowNode.node .input []
      (events := [{ kind := .input, eventName := "rename" }])]
  ]
  let typedRegion : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := typedTemplate
        events := #[{ name := "remove", action := .remove }, renameEvent] }] }
  match typedRegion.check with
  | .error error =>
      throw <| IO.userError s!"forged typed row region rejected: {error.code}"
  | .ok _ => pure ()
  let payloadInTemplate : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.exprText .payload] }] }
  expectError "LRX-VIEW-033" payloadInTemplate.check
  let payloadWithoutDeclaration : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        events := #[{ name := "remove", action := .remove },
          { name := "sneak", action := .update ⟨[(0, .payload)], none⟩ }] }] }
  expectError "LRX-VIEW-033" payloadWithoutDeclaration.check
  let typedOnClick : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [
          RowNode.node .span [RowNode.node .button [RowNode.text "r"]
            (attrs := [.buttonType .button])
            (events := [{ kind := .click, eventName := "rename" }])]]
        events := #[{ name := "remove", action := .remove }, renameEvent] }] }
  expectError "LRX-VIEW-033" typedOnClick.check
  let inputBindingOnPayloadless : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [
          RowNode.node .span [RowNode.node .input []
            (events := [{ kind := .input, eventName := "remove" }])]] }] }
  expectError "LRX-VIEW-033" inputBindingOnPayloadless.check
  let inputBindingOnSpan : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [
          RowNode.node .span [RowNode.node .span [RowNode.text "x"]
            (events := [{ kind := .input, eventName := "rename" }])]]
        events := #[{ name := "remove", action := .remove }, renameEvent] }] }
  expectError "LRX-VIEW-033" inputBindingOnSpan.check
  let unboundTypedEvent : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        events := #[{ name := "remove", action := .remove }, renameEvent] }] }
  expectError "LRX-VIEW-033" unboundTypedEvent.check
  /- ADR-0047 sealed two-branch row cells and value reflections, exercised
  through forged specifications. -/
  let editEvent : RowEventSpec :=
    { name := "edit", action := .update ⟨[(1, .lit "edit")], none⟩ }
  let retypeEvent : RowEventSpec :=
    { name := "retype", action := .update ⟨[(0, .payload)], none⟩, takesPayload := true }
  let branchCell : RowNode := RowNode.branch 1 "view"
    (RowNode.node .span [RowNode.fieldText 0])
    (RowNode.node .input [] (events := [{ kind := .input, eventName := "retype" }])
      (reflects := [{ value := .field 0 }]))
  let branchTemplate : RowNode := RowNode.node .li [
    branchCell,
    RowNode.node .span [RowNode.node .button [RowNode.text "e"]
      (attrs := [.buttonType .button])
      (events := [{ kind := .click, eventName := "edit" }])]
  ]
  let branchRegion : RegionSpec := {
    name := "r"
    fields := #["label", "mode"]
    template := branchTemplate
    events := #[{ name := "remove", action := .remove }, editEvent, retypeEvent]
  }
  let branchSpec : ComponentSpec CounterSchema :=
    { spec with view := regionView, regions := #[branchRegion] }
  match branchSpec.check with
  | .error error =>
      throw <| IO.userError s!"forged branch region rejected: {error.code}"
  | .ok _ => pure ()
  let nestedBranch : ComponentSpec CounterSchema :=
    { branchSpec with regions := #[{ branchRegion with
        template := RowNode.node .li [RowNode.node .span [branchCell]] }] }
  expectError "LRX-VIEW-034" nestedBranch.check
  let branchFieldOutOfBounds : ComponentSpec CounterSchema :=
    { branchSpec with regions := #[{ branchRegion with
        template := RowNode.node .li [RowNode.branch 2 "view"
          (RowNode.node .span [RowNode.fieldText 0])
          (RowNode.node .span [RowNode.fieldText 0])]
        events := #[{ name := "remove", action := .remove }, editEvent] }] }
  expectError "LRX-VIEW-026" branchFieldOutOfBounds.check
  let textBranch : ComponentSpec CounterSchema :=
    { branchSpec with regions := #[{ branchRegion with
        template := RowNode.node .li [RowNode.branch 1 "view"
          (RowNode.node .span [RowNode.fieldText 0]) (RowNode.text "x")]
        events := #[{ name := "remove", action := .remove }, editEvent] }] }
  expectError "LRX-VIEW-034" textBranch.check
  let oneSidedClick : ComponentSpec CounterSchema :=
    { branchSpec with regions := #[{ branchRegion with
        template := RowNode.node .li [RowNode.branch 1 "view"
          (RowNode.node .span [RowNode.node .button [RowNode.text "e"]
            (attrs := [.buttonType .button])
            (events := [{ kind := .click, eventName := "edit" }])])
          (RowNode.node .span [RowNode.fieldText 0])] }] }
  expectError "LRX-VIEW-034" oneSidedClick.check
  let disagreeingClicks : ComponentSpec CounterSchema :=
    { branchSpec with regions := #[{ branchRegion with
        template := RowNode.node .li [RowNode.branch 1 "view"
          (RowNode.node .span [RowNode.node .button [RowNode.text "e"]
            (attrs := [.buttonType .button])
            (events := [{ kind := .click, eventName := "edit" }])])
          (RowNode.node .span [RowNode.node .button [RowNode.text "r"]
            (attrs := [.buttonType .button])
            (events := [{ kind := .click, eventName := "remove" }])])] }] }
  expectError "LRX-VIEW-034" disagreeingClicks.check
  let inputInUnboundBranch : ComponentSpec CounterSchema :=
    { branchSpec with regions := #[{ branchRegion with
        template := RowNode.node .li [RowNode.branch 1 "view"
          (RowNode.node .span [RowNode.node .input []])
          (RowNode.node .input []
            (events := [{ kind := .input, eventName := "retype" }]))] }] }
  expectError "LRX-VIEW-034" inputInUnboundBranch.check
  let stampEvent : RowEventSpec :=
    { name := "stamp", action := .update ⟨[(0, .payload)], none⟩, takesPayload := true }
  let buttonInUnboundKeydownBranch : ComponentSpec CounterSchema :=
    { branchSpec with regions := #[{ branchRegion with
        template := RowNode.node .li [RowNode.branch 1 "view"
          (RowNode.node .span [RowNode.node .button [RowNode.text "b"]
            (attrs := [.buttonType .button])])
          (RowNode.node .input []
            (events := [{ kind := .keydown, eventName := "stamp" }]))]
        events := #[{ name := "remove", action := .remove }, stampEvent] }] }
  expectError "LRX-VIEW-034" buttonInUnboundKeydownBranch.check
  let reflectOnSpan : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.node .span [RowNode.fieldText 0]
          (reflects := [{ value := .field 0 }])] }] }
  expectError "LRX-VIEW-035" reflectOnSpan.check
  let doubleReflect : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.node .span [RowNode.node .input []
          (reflects := [{ value := .field 0 }, { value := .lit "x" }])]] }] }
  expectError "LRX-VIEW-035" doubleReflect.check
  let payloadReflect : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.node .span [RowNode.node .input []
          (reflects := [{ value := .payload }])]] }] }
  expectError "LRX-VIEW-033" payloadReflect.check
  let reflectOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.node .span [RowNode.node .input []
          (reflects := [{ value := .field 1 }])]] }] }
  expectError "LRX-VIEW-026" reflectOutOfBounds.check
  /- ADR-0048 autoFocus markers, exercised through forged specifications:
  a marked branch input passes; a marked span, a marked input outside a
  branch subtree, and a doubly marked subtree are rejected. -/
  let focusedBranchSpec : ComponentSpec CounterSchema :=
    { branchSpec with regions := #[{ branchRegion with
        template := RowNode.node .li [
          RowNode.branch 1 "view"
            (RowNode.node .span [RowNode.fieldText 0])
            (RowNode.node .input []
              (events := [{ kind := .input, eventName := "retype" }])
              (reflects := [{ value := .field 0 }]) (autoFocus := true)),
          RowNode.node .span [RowNode.node .button [RowNode.text "e"]
            (attrs := [.buttonType .button])
            (events := [{ kind := .click, eventName := "edit" }])]] }] }
  match focusedBranchSpec.check with
  | .error error =>
      throw <| IO.userError s!"forged autoFocus branch rejected: {error.code}"
  | .ok _ => pure ()
  let focusOnSpan : ComponentSpec CounterSchema :=
    { branchSpec with regions := #[{ branchRegion with
        template := RowNode.node .li [RowNode.branch 1 "view"
          (RowNode.node .span [RowNode.fieldText 0] (autoFocus := true))
          (RowNode.node .span [RowNode.fieldText 0])]
        events := #[{ name := "remove", action := .remove }, editEvent] }] }
  expectError "LRX-VIEW-036" focusOnSpan.check
  let focusOutsideBranch : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [RowNode.node .span [RowNode.node .input []
          (events := [{ kind := .input, eventName := "rename" }])
          (autoFocus := true)]]
        events := #[{ name := "remove", action := .remove }, renameEvent] }] }
  expectError "LRX-VIEW-036" focusOutsideBranch.check
  let doubleFocusInSubtree : ComponentSpec CounterSchema :=
    { branchSpec with regions := #[{ branchRegion with
        template := RowNode.node .li [RowNode.branch 1 "view"
          (RowNode.node .span [RowNode.fieldText 0])
          (RowNode.node .span [
            RowNode.node .input []
              (events := [{ kind := .input, eventName := "retype" }])
              (autoFocus := true),
            RowNode.node .input [] (autoFocus := true)])] }] }
  expectError "LRX-VIEW-036" doubleFocusInSubtree.check
  /- ADR-0049 delegated dblclick and checkbox change kinds, exercised through
  forged specifications: a five-kind template with the checked reflection
  passes; the checkbox-origin rules, the dblclick agreement rules, and the
  payload classes are rejected. -/
  let toggleEvent : RowEventSpec :=
    { name := "toggle", action := .update ⟨[(1, .payload)], none⟩, takesPayload := true }
  let toggleEditEvent : RowEventSpec :=
    { name := "edit", action := .update ⟨[(2, .lit "edit")], none⟩ }
  let toggleRegion : RegionSpec := {
    name := "r"
    fields := #["label", "done", "mode"]
    template := RowNode.node .li [
      RowNode.node .span [RowNode.node .input [] (attrs := [.inputType .checkbox])
        (events := [{ kind := .checkedChange, eventName := "toggle" }])
        (reflects := [{ value := .field 1, target := .checkedIf "true" }])],
      RowNode.branch 2 "view"
        (RowNode.node .span [RowNode.fieldText 0]
          (events := [{ kind := .dblclick, eventName := "edit" }]))
        (RowNode.node .span [RowNode.fieldText 0]
          (events := [{ kind := .dblclick, eventName := "edit" }])),
      RowNode.node .span [RowNode.node .button [RowNode.text "x"]
        (attrs := [.buttonType .button])
        (events := [{ kind := .click, eventName := "remove" }])]
    ]
    events := #[{ name := "remove", action := .remove }, toggleEvent, toggleEditEvent]
  }
  let toggleSpec : ComponentSpec CounterSchema :=
    { spec with view := regionView, regions := #[toggleRegion] }
  match toggleSpec.check with
  | .error error =>
      throw <| IO.userError s!"forged five-kind region rejected: {error.code}"
  | .ok _ => pure ()
  let changeOnTextInput : ComponentSpec CounterSchema :=
    { toggleSpec with regions := #[{ toggleRegion with
        template := RowNode.node .li [RowNode.node .span [RowNode.node .input []
          (events := [{ kind := .checkedChange, eventName := "toggle" }])]]
        events := #[{ name := "remove", action := .remove }, toggleEvent] }] }
  expectError "LRX-VIEW-037" changeOnTextInput.check
  let checkedReflectOnTextInput : ComponentSpec CounterSchema :=
    { toggleSpec with regions := #[{ toggleRegion with
        template := RowNode.node .li [RowNode.node .span [RowNode.node .input []
          (reflects := [{ value := .field 1, target := .checkedIf "true" }])]]
        events := #[{ name := "remove", action := .remove }] }] }
  expectError "LRX-VIEW-037" checkedReflectOnTextInput.check
  let doubleCheckedReflect : ComponentSpec CounterSchema :=
    { toggleSpec with regions := #[{ toggleRegion with
        template := RowNode.node .li [RowNode.node .span [RowNode.node .input []
          (attrs := [.inputType .checkbox])
          (reflects := [{ value := .field 1, target := .checkedIf "true" },
            { value := .field 2, target := .checkedIf "edit" }])]]
        events := #[{ name := "remove", action := .remove }] }] }
  expectError "LRX-VIEW-035" doubleCheckedReflect.check
  let checkedReflectOutOfBounds : ComponentSpec CounterSchema :=
    { toggleSpec with regions := #[{ toggleRegion with
        template := RowNode.node .li [RowNode.node .span [RowNode.node .input []
          (attrs := [.inputType .checkbox])
          (reflects := [{ value := .field 3, target := .checkedIf "true" }])]]
        events := #[{ name := "remove", action := .remove }] }] }
  expectError "LRX-VIEW-026" checkedReflectOutOfBounds.check
  let oneSidedDblClick : ComponentSpec CounterSchema :=
    { toggleSpec with regions := #[{ toggleRegion with
        template := RowNode.node .li [RowNode.branch 2 "view"
          (RowNode.node .span [RowNode.fieldText 0]
            (events := [{ kind := .dblclick, eventName := "edit" }]))
          (RowNode.node .span [RowNode.fieldText 0])]
        events := #[{ name := "remove", action := .remove }, toggleEditEvent] }] }
  expectError "LRX-VIEW-034" oneSidedDblClick.check
  let inputInUnboundChangeBranch : ComponentSpec CounterSchema :=
    { toggleSpec with regions := #[{ toggleRegion with
        template := RowNode.node .li [RowNode.branch 2 "view"
          (RowNode.node .span [RowNode.node .input [] (attrs := [.inputType .checkbox])
            (events := [{ kind := .checkedChange, eventName := "toggle" }])])
          (RowNode.node .span [RowNode.node .input []])]
        events := #[{ name := "remove", action := .remove }, toggleEvent] }] }
  expectError "LRX-VIEW-034" inputInUnboundChangeBranch.check
  let dblClickOnTypedEvent : ComponentSpec CounterSchema :=
    { toggleSpec with regions := #[{ toggleRegion with
        template := RowNode.node .li [RowNode.node .span [
          RowNode.node .span [RowNode.fieldText 0]
            (events := [{ kind := .dblclick, eventName := "toggle" }])]]
        events := #[{ name := "remove", action := .remove }, toggleEvent] }] }
  expectError "LRX-VIEW-033" dblClickOnTypedEvent.check
  /- ADR-0050 region broadcasts, predicate removals, and sealed row
  aggregates, exercised through forged specifications. -/
  let broadcastSpec : ComponentSpec CounterSchema :=
    { goodRegion with events := #[{
        name := "stampAll"
        update := .regionBroadcast "r" [(0, .append (.field 0) (.lit "!"))]
      }] }
  match broadcastSpec.check with
  | .error error =>
      throw <| IO.userError s!"forged region broadcast rejected: {error.code}"
  | .ok checked =>
      match checked.spec.events.toList.find? (·.name == "stampAll") with
      | none => throw <| IO.userError "forged broadcast event disappeared"
      | some event =>
          unless event.update.regionBroadcastTargets ==
              [("r", [(0, .append (.field 0) (.lit "!"))])] do
            throw <| IO.userError "forged broadcast lost its target or assignments"
  let broadcastUnknownRegion : ComponentSpec CounterSchema :=
    { goodRegion with events := #[{
        name := "bad", update := .regionBroadcast "ghost" [(0, .lit "x")] }] }
  expectError "LRX-TYPE-111" broadcastUnknownRegion.check
  let broadcastEmpty : ComponentSpec CounterSchema :=
    { goodRegion with events := #[{
        name := "bad", update := .regionBroadcast "r" [] }] }
  expectError "LRX-TYPE-111" broadcastEmpty.check
  let broadcastDuplicateTarget : ComponentSpec CounterSchema :=
    { goodRegion with events := #[{
        name := "bad", update := .regionBroadcast "r" [(0, .lit "x"), (0, .lit "y")] }] }
  expectError "LRX-TYPE-111" broadcastDuplicateTarget.check
  let broadcastTargetOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with events := #[{
        name := "bad", update := .regionBroadcast "r" [(1, .lit "x")] }] }
  expectError "LRX-TYPE-111" broadcastTargetOutOfBounds.check
  let broadcastPayload : ComponentSpec CounterSchema :=
    { goodRegion with events := #[{
        name := "bad", update := .regionBroadcast "r" [(0, .payload)] }] }
  expectError "LRX-TYPE-111" broadcastPayload.check
  let broadcastReadOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with events := #[{
        name := "bad", update := .regionBroadcast "r" [(0, .field 1)] }] }
  expectError "LRX-TYPE-111" broadcastReadOutOfBounds.check
  /- ADR-0061 payload broadcast events, exercised through forged
  specifications: the Bool checked payload of one typed component event
  flows into a region broadcast as a bare set right-hand side — no state
  target, no state write in its summary, and the checked-change binding
  resolves it through the ADR-0038 payload table. -/
  let payloadBroadcast : AnyTypedEvent CounterSchema := .boolBroadcast {
    name := "toggleAll", parameterName := "checked"
    region := "r", assignments := [(0, .payload)] }
  let payloadBroadcastSpec : ComponentSpec CounterSchema :=
    { goodRegion with
        view := View.node .main [
          View.node .input [] (attrs := [.inputType .checkbox])
            (events := [{ kind := .checkedChange, eventName := "toggleAll" }]),
          View.node .ul [View.region "r"]]
        typedEvents := #[payloadBroadcast] }
  match payloadBroadcastSpec.check with
  | .error error =>
      throw <| IO.userError s!"forged payload broadcast rejected: {error.code}"
  | .ok checked =>
      unless checked.spec.typedEvents.toList.map (fun event =>
          (event.name, event.broadcast?, event.targetIndex?,
            event.payloadType.debug)) ==
          [("toggleAll", some ("r", [(0, .payload)]), none, "bool")] do
        throw <| IO.userError "forged payload broadcast lost its body"
      match checked.eventSummaries.toList.find? (·.name == "toggleAll") with
      | none => throw <| IO.userError "forged payload broadcast summary disappeared"
      | some summary =>
          unless summary.directWrites.isEmpty && summary.effectiveWrites.isEmpty do
            throw <| IO.userError "forged payload broadcast summary gained state writes"
  let payloadBroadcastOnValue : ComponentSpec CounterSchema :=
    { payloadBroadcastSpec with
        view := View.node .main [
          View.node .input []
            (events := [{ kind := .input, eventName := "toggleAll" }]),
          View.node .ul [View.region "r"]] }
  expectError "LRX-VIEW-018" payloadBroadcastOnValue.check
  let payloadBroadcastUnknownRegion : ComponentSpec CounterSchema :=
    { goodRegion with typedEvents := #[.boolBroadcast {
        name := "bad", parameterName := "checked"
        region := "ghost", assignments := [(0, .payload)] }] }
  expectError "LRX-TYPE-116" payloadBroadcastUnknownRegion.check
  let payloadBroadcastEmpty : ComponentSpec CounterSchema :=
    { goodRegion with typedEvents := #[.boolBroadcast {
        name := "bad", parameterName := "checked"
        region := "r", assignments := [] }] }
  expectError "LRX-TYPE-116" payloadBroadcastEmpty.check
  let payloadBroadcastDuplicate : ComponentSpec CounterSchema :=
    { goodRegion with typedEvents := #[.boolBroadcast {
        name := "bad", parameterName := "checked"
        region := "r", assignments := [(0, .payload), (0, .lit "x")] }] }
  expectError "LRX-TYPE-116" payloadBroadcastDuplicate.check
  let payloadBroadcastTargetOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with typedEvents := #[.boolBroadcast {
        name := "bad", parameterName := "checked"
        region := "r", assignments := [(1, .payload)] }] }
  expectError "LRX-TYPE-116" payloadBroadcastTargetOutOfBounds.check
  let payloadBroadcastComposed : ComponentSpec CounterSchema :=
    { goodRegion with typedEvents := #[.boolBroadcast {
        name := "bad", parameterName := "checked"
        region := "r", assignments := [(0, .trim .payload)] }] }
  expectError "LRX-TYPE-116" payloadBroadcastComposed.check
  let payloadBroadcastNeverWrites : ComponentSpec CounterSchema :=
    { goodRegion with typedEvents := #[.boolBroadcast {
        name := "bad", parameterName := "checked"
        region := "r", assignments := [(0, .lit "x")] }] }
  expectError "LRX-TYPE-116" payloadBroadcastNeverWrites.check
  let payloadBroadcastReadOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with
        regions := #[{ rosterRegion with fields := #["label", "done"] }]
        typedEvents := #[.boolBroadcast {
          name := "bad", parameterName := "checked"
          region := "r", assignments := [(0, .payload), (1, .field 5)] }] }
  expectError "LRX-TYPE-116" payloadBroadcastReadOutOfBounds.check
  let removeIfUnknownRegion : ComponentSpec CounterSchema :=
    { goodRegion with events := #[{
        name := "bad", update := .regionRemoveIf "ghost" (.ofField 0 "x") }] }
  expectError "LRX-TYPE-112" removeIfUnknownRegion.check
  let removeIfOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with events := #[{
        name := "bad", update := .regionRemoveIf "r" (.ofField 1 "x") }] }
  expectError "LRX-TYPE-112" removeIfOutOfBounds.check
  let countingView : View CounterSchema := View.node .main [
    View.node .ul [View.region "r"],
    View.node .p [View.regionCount "r" (some (0, "done")), View.regionCount "r" none,
      View.regionCount "r" (some (0, "done")) .generated (some (" one", " many"))]
  ]
  let countingRegion : ComponentSpec CounterSchema :=
    { goodRegion with view := countingView }
  match countingRegion.check with
  | .error error =>
      throw <| IO.userError s!"forged region counts rejected: {error.code}"
  | .ok checked =>
      unless checked.view.regionCounts.map
          (fun count => (count.region, count.predicate, count.label, count.path)) ==
          [("r", some (0, "done"), none, [1, 0]), ("r", none, none, [1, 1]),
            ("r", some (0, "done"), some (" one", " many"), [1, 2])] do
        throw <| IO.userError "forged region counts lost their mounted positions"
  let countUnknownRegion : ComponentSpec CounterSchema :=
    { goodRegion with view := View.node .main [
        View.node .ul [View.region "r"],
        View.node .p [View.regionCount "ghost" none]] }
  expectError "LRX-VIEW-038" countUnknownRegion.check
  let countPredicateOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with view := View.node .main [
        View.node .ul [View.region "r"],
        View.node .p [View.regionCount "r" (some (1, "x"))]] }
  expectError "LRX-VIEW-038" countPredicateOutOfBounds.check
  /- The ADR-0062 label count carries the same ADR-0050 obligations: an
  unknown region and an out-of-bounds predicate field reject identically
  with the label present. -/
  let labelUnknownRegion : ComponentSpec CounterSchema :=
    { goodRegion with view := View.node .main [
        View.node .ul [View.region "r"],
        View.node .p [View.regionCount "ghost" none .generated (some ("a", "b"))]] }
  expectError "LRX-VIEW-038" labelUnknownRegion.check
  let labelPredicateOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with view := View.node .main [
        View.node .ul [View.region "r"],
        View.node .p [View.regionCount "r" (some (1, "x")) .generated
          (some ("a", "b"))]] }
  expectError "LRX-VIEW-038" labelPredicateOutOfBounds.check
  /- ADR-0051 sealed region filter views, exercised through forged
  specifications: the good filter checks, keeps its arm table, and joins the
  planned graph as a sink node; LRX-TYPE-113 rejects the unknown region, the
  empty and duplicate arm tables, the out-of-bounds predicate field, and a
  second filter on one region. -/
  let goodFilter : ComponentSpec CounterSchema :=
    { goodRegion with filters := #[{
        region := "r", field := parity, arms := [("odd", .ofField 0 "x")] }] }
  match goodFilter.check with
  | .error error =>
      throw <| IO.userError s!"forged region filter rejected: {error.code}"
  | .ok checked =>
      unless checked.spec.filters.map
          (fun filter => (filter.region, filter.field.index, filter.arms)) ==
          #[("r", 2, [("odd", .ofField 0 "x")])] do
        throw <| IO.userError "forged region filter lost its arm table"
      unless (checked.graph.graph.nodes.map (·.name)).contains "filter:0:r" do
        throw <| IO.userError "forged region filter lost its graph sink node"
  let filterUnknownRegion : ComponentSpec CounterSchema :=
    { goodRegion with filters := #[{
        region := "ghost", field := parity, arms := [("odd", .ofField 0 "x")] }] }
  expectError "LRX-TYPE-113" filterUnknownRegion.check
  let filterNoArms : ComponentSpec CounterSchema :=
    { goodRegion with filters := #[{ region := "r", field := parity, arms := [] }] }
  expectError "LRX-TYPE-113" filterNoArms.check
  let filterDuplicateLiteral : ComponentSpec CounterSchema :=
    { goodRegion with filters := #[{
        region := "r", field := parity, arms := [("odd", .ofField 0 "x"), ("odd", .ofField 0 "y")] }] }
  expectError "LRX-TYPE-113" filterDuplicateLiteral.check
  let filterFieldOutOfBounds : ComponentSpec CounterSchema :=
    { goodRegion with filters := #[{
        region := "r", field := parity, arms := [("odd", .ofField 1 "x")] }] }
  expectError "LRX-TYPE-113" filterFieldOutOfBounds.check
  let filterDuplicateRegion : ComponentSpec CounterSchema :=
    { goodRegion with filters := #[
        { region := "r", field := parity, arms := [("odd", .ofField 0 "x")] },
        { region := "r", field := parity, arms := [("even", .ofField 0 "y")] }] }
  expectError "LRX-TYPE-113" filterDuplicateRegion.check
  /- ADR-0052 key-branched row events, exercised through forged
  specifications: the good selection checks and keeps its arm table;
  LRX-VIEW-039 rejects the payload-less spec, the empty and duplicate arm
  tables, a key outside the sealed Enter/Escape set, the per-arm update
  violations (empty, duplicate target, out-of-bounds writes and reads, a
  payload reference in an arm), and every non-keydown binding. -/
  let keysEvent : RowEventSpec :=
    { name := "keys"
      action := .keySelect [
        ("Enter", ⟨[(0, .lit "committed")], none⟩), ("Escape", ⟨[(0, .lit "reverted")], none⟩)]
      takesPayload := true }
  let keysTemplate : RowNode := RowNode.node .li [
    RowNode.node .span [RowNode.fieldText 0],
    RowNode.node .span [RowNode.node .input []
      (events := [{ kind := .keydown, eventName := "keys" }])]
  ]
  let goodKeys : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := keysTemplate
        events := #[{ name := "remove", action := .remove }, keysEvent] }] }
  match goodKeys.check with
  | .error error =>
      throw <| IO.userError s!"forged key-branched region rejected: {error.code}"
  | .ok checked =>
      unless checked.spec.regions.toList.map (fun region =>
          region.events.toList.map fun event =>
            (event.name, event.action, event.takesPayload)) ==
          [[("remove", .remove, false), ("keys", keysEvent.action, true)]] do
        throw <| IO.userError "forged key-branched region lost its arm table"
  let withKeys (event : RowEventSpec) : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := keysTemplate
        events := #[{ name := "remove", action := .remove }, event] }] }
  expectError "LRX-VIEW-039" (withKeys { keysEvent with takesPayload := false }).check
  expectError "LRX-VIEW-039" (withKeys { keysEvent with action := .keySelect [] }).check
  expectError "LRX-VIEW-039" (withKeys { keysEvent with action := .keySelect [
    ("Enter", ⟨[(0, .lit "a")], none⟩), ("Enter", ⟨[(0, .lit "b")], none⟩)] }).check
  expectError "LRX-VIEW-039" (withKeys { keysEvent with action := .keySelect [
    ("Tab", ⟨[(0, .lit "a")], none⟩)] }).check
  expectError "LRX-VIEW-039" (withKeys { keysEvent with action := .keySelect [
    ("Enter", ⟨[], none⟩)] }).check
  expectError "LRX-VIEW-039" (withKeys { keysEvent with action := .keySelect [
    ("Enter", ⟨[(0, .lit "a"), (0, .lit "b")], none⟩)] }).check
  expectError "LRX-VIEW-039" (withKeys { keysEvent with action := .keySelect [
    ("Enter", ⟨[(1, .lit "a")], none⟩)] }).check
  expectError "LRX-VIEW-039" (withKeys { keysEvent with action := .keySelect [
    ("Enter", ⟨[(0, .payload)], none⟩)] }).check
  expectError "LRX-VIEW-039" (withKeys { keysEvent with action := .keySelect [
    ("Enter", ⟨[(0, .field 1)], none⟩)] }).check
  let keysBoundAsInput : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := RowNode.node .li [
          RowNode.node .span [RowNode.fieldText 0],
          RowNode.node .span [RowNode.node .input []
            (events := [{ kind := .input, eventName := "keys" }])]]
        events := #[{ name := "remove", action := .remove }, keysEvent] }] }
  expectError "LRX-VIEW-039" keysBoundAsInput.check
  /- ADR-0053 remove-if guards, exercised through forged specifications: the
  good guarded update and guarded key arm check and keep their guards;
  LRX-VIEW-040 rejects an out-of-bounds guard field on both stage positions
  and a guarded stage on a payload-taking row event — guards live on
  payload-less row events and key arms. -/
  let chopEvent : RowEventSpec :=
    { name := "chop", action := .update ⟨[(0, .lit "x")], some ⟨.field 0, ""⟩⟩ }
  let choppingTemplate : RowNode := RowNode.node .li [
    RowNode.node .span [RowNode.fieldText 0],
    RowNode.node .span [RowNode.node .button [RowNode.text "c"]
      (attrs := [.buttonType .button])
      (events := [{ kind := .click, eventName := "chop" }])]
  ]
  let withChop (event : RowEventSpec) : ComponentSpec CounterSchema :=
    { goodRegion with regions := #[{ rosterRegion with
        template := choppingTemplate
        events := #[{ name := "remove", action := .remove }, event] }] }
  match (withChop chopEvent).check with
  | .error error =>
      throw <| IO.userError s!"forged guarded row event rejected: {error.code}"
  | .ok checked =>
      unless checked.spec.regions.toList.map (fun region =>
          region.events.toList.map fun event => (event.name, event.action)) ==
          [[("remove", .remove), ("chop", chopEvent.action)]] do
        throw <| IO.userError "forged guarded row event lost its guard"
  expectError "LRX-VIEW-040" (withChop { chopEvent with
    action := .update ⟨[(0, .lit "x")], some ⟨.field 1, ""⟩⟩ }).check
  expectError "LRX-VIEW-040" (withChop { chopEvent with
    action := .update ⟨[(0, .payload)], some ⟨.field 0, ""⟩⟩
    takesPayload := true }).check
  /- ADR-0054 trimmed guards and trimmed commits: the trimmed subject and
  trimmed assignment check and keep their expressions; LRX-VIEW-040 rejects
  every non-subject guard expression — a literal, a trimmed literal, a
  payload, a concatenation — and an out-of-bounds trimmed field. -/
  let trimEvent : RowEventSpec :=
    { name := "chop",
      action := .update ⟨[(0, .trim (.field 0))], some ⟨.trim (.field 0), ""⟩⟩ }
  match (withChop trimEvent).check with
  | .error error =>
      throw <| IO.userError s!"forged trimmed guarded row event rejected: {error.code}"
  | .ok checked =>
      unless checked.spec.regions.toList.map (fun region =>
          region.events.toList.map fun event => (event.name, event.action)) ==
          [[("remove", .remove), ("chop", trimEvent.action)]] do
        throw <| IO.userError "forged trimmed guarded row event lost its trim"
  expectError "LRX-VIEW-040" (withChop { chopEvent with
    action := .update ⟨[(0, .lit "x")], some ⟨.lit "x", ""⟩⟩ }).check
  expectError "LRX-VIEW-040" (withChop { chopEvent with
    action := .update ⟨[(0, .lit "x")], some ⟨.trim (.lit "x"), ""⟩⟩ }).check
  expectError "LRX-VIEW-040" (withChop { chopEvent with
    action := .update ⟨[(0, .lit "x")], some ⟨.payload, ""⟩⟩ }).check
  expectError "LRX-VIEW-040" (withChop { chopEvent with
    action := .update ⟨[(0, .lit "x")],
      some ⟨.append (.field 0) (.field 0), ""⟩⟩ }).check
  expectError "LRX-VIEW-040" (withChop { chopEvent with
    action := .update ⟨[(0, .lit "x")], some ⟨.trim (.field 1), ""⟩⟩ }).check
  let guardedKeys : RowEventSpec :=
    { keysEvent with action := .keySelect [
        ("Enter", ⟨[(0, .lit "committed")], some ⟨.field 0, ""⟩⟩),
        ("Escape", ⟨[(0, .lit "reverted")], none⟩)] }
  match (withKeys guardedKeys).check with
  | .error error =>
      throw <| IO.userError s!"forged guarded key arm rejected: {error.code}"
  | .ok checked =>
      unless checked.spec.regions.toList.map (fun region =>
          region.events.toList.map (·.action)) ==
          [[.remove, guardedKeys.action]] do
        throw <| IO.userError "forged guarded key arm lost its guard"
  expectError "LRX-VIEW-040" (withKeys { keysEvent with action := .keySelect [
    ("Enter", ⟨[(0, .lit "a")], some ⟨.field 2, ""⟩⟩)] }).check
  /- The ADR-0054 trimmed guard subject on a key arm: the trimmed selection
  checks, and a non-subject arm guard is rejected. -/
  match (withKeys { keysEvent with action := .keySelect [
      ("Enter", ⟨[(0, .trim (.field 0))], some ⟨.trim (.field 0), ""⟩⟩)] }).check with
  | .error error =>
      throw <| IO.userError s!"forged trimmed guarded key arm rejected: {error.code}"
  | .ok _ => pure ()
  expectError "LRX-VIEW-040" (withKeys { keysEvent with action := .keySelect [
    ("Enter", ⟨[(0, .lit "a")], some ⟨.trim .payload, ""⟩⟩)] }).check
  /- ADR-0055 sealed component-event skip guards, exercised through forged
  specifications: a guarded event over a String source checks, keeps its
  guard, and records the guard read in its summary; LRX-TYPE-114 rejects a
  guard on a derived value — the `Field Γ String` type already makes a
  cross-typed or out-of-bounds subject unrepresentable, and the empty
  literal is fixed by construction. -/
  let guardedSpec : ComponentSpec (.field "draft" String .empty) :=
    { name := "Guarded"
      values := #[ValueSpec.state
        (.here : Field (.field "draft" String .empty) String) (.string "")]
      events := #[{
        name := "add"
        update := .set (.here : Field (.field "draft" String .empty) String)
          (RxExpr.literal (.string ""))
        guard? := some { field := .here, trimmed := true }
      }]
      view := View.node .p [.text "guarded"] }
  match guardedSpec.check with
  | .error error =>
      throw <| IO.userError s!"forged guarded event rejected: {error.code}"
  | .ok checked =>
      unless checked.spec.events.toList.map (fun event =>
          event.guard?.map fun guard => (guard.field.index, guard.trimmed)) ==
          [some (0, true)] do
        throw <| IO.userError "forged guarded event lost its guard"
      unless checked.eventSummaries.toList.map (·.directReads) == [[0]] do
        throw <| IO.userError "forged guarded event summary lost the guard read"
  let guardOnDerived : ComponentSpec CounterSchema :=
    { spec with events := #[{
        name := "badGuard"
        update := .set count (RxExpr.literal (.int 0))
        guard? := some { field := parity, trimmed := false }
      }] }
  expectError "LRX-TYPE-114" guardOnDerived.check
  /- ADR-0056 sealed key-branched component events, exercised through forged
  specifications: a keydown-bound Enter arm behind the ADR-0055 guard checks,
  keeps its arm table, and records the guard read in its summary union;
  LRX-TYPE-115 rejects a key outside the sealed Enter/Escape set, a
  duplicated key, and an empty arm table; LRX-VIEW-041 rejects a non-keydown
  binding and an unbound (or multiply bound) key event. -/
  let keyedArm : KeyEventArm (.field "draft" String .empty) := {
    key := "Enter"
    update := .set (.here : Field (.field "draft" String .empty) String)
      (RxExpr.literal (.string ""))
    guard? := some { field := .here, trimmed := true }
  }
  let keyedSpec : ComponentSpec (.field "draft" String .empty) :=
    { name := "Keyed"
      values := #[ValueSpec.state
        (.here : Field (.field "draft" String .empty) String) (.string "")]
      events := #[]
      keyEvents := #[{
        name := "confirm"
        parameterName := "pressed"
        arms := [keyedArm]
      }]
      view := View.node .main [View.node .input []
        (events := [{ kind := .keydown, eventName := "confirm" }])] }
  match keyedSpec.check with
  | .error error =>
      throw <| IO.userError s!"forged key-branched event rejected: {error.code}"
  | .ok checked =>
      unless checked.spec.keyEvents.toList.map (fun event =>
          (event.name, event.parameterName, event.arms.map fun arm =>
            (arm.key, arm.guard?.map fun guard =>
              (guard.field.index, guard.trimmed)))) ==
          [("confirm", "pressed", [("Enter", some (0, true))])] do
        throw <| IO.userError "forged key-branched event lost its arm table"
      unless checked.eventSummaries.toList.map (fun s => (s.name, s.directReads)) ==
          [("confirm", [0])] do
        throw <| IO.userError "forged key-branched event summary lost the guard read"
  expectError "LRX-TYPE-115" ({ keyedSpec with keyEvents := #[{
    name := "confirm"
    parameterName := "pressed"
    arms := [{ keyedArm with key := "Tab" }]
  }] }).check
  expectError "LRX-TYPE-115" ({ keyedSpec with keyEvents := #[{
    name := "confirm"
    parameterName := "pressed"
    arms := [keyedArm, keyedArm]
  }] }).check
  expectError "LRX-TYPE-115" ({ keyedSpec with keyEvents := #[{
    name := "confirm"
    parameterName := "pressed"
    arms := []
  }] }).check
  expectError "LRX-VIEW-041" ({ keyedSpec with view := View.node .main [
    View.node .input [] (events := [{ kind := .input, eventName := "confirm" }])] }).check
  expectError "LRX-VIEW-041" ({ keyedSpec with
    view := View.node .p [.text "unbound"] }).check
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
