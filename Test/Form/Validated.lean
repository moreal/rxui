import LeanRx.Form.Validated

namespace LeanRxTest.Form.Validated

open LeanRx LeanRx.Form

def spec : ValidatedFormSpec :=
  ValidatedFormSpec.create "Validated Form" { name := "", age := "17", accepted := false }

def run : IO Unit := do
  match spec.check with
  | .error error => throw <| IO.userError s!"validated form model failed: {error.code}"
  | .ok checked =>
      unless checked.graph.graph.nodes.map (·.rank) == #[0, 0, 0, 1, 1, 1, 1] do
        throw <| IO.userError "validated form graph gained a cycle or unstable ranks"
      unless checked.nameControl.payloadType == .string && checked.nameControl.target.index == 0 &&
          checked.nameControl.event.name == "input" && checked.nameControl.property.name == "value" &&
          checked.ageControl.payloadType == .string && checked.ageControl.target.index == 1 &&
          checked.ageControl.event.name == "change" && checked.ageControl.property.name == "value" &&
          checked.acceptedControl.payloadType == .bool && checked.acceptedControl.target.index == 2 &&
          checked.acceptedControl.event.payloadKind == .checked &&
          checked.acceptedControl.property.name == "checked" do
        throw <| IO.userError "validated form typed payloads drifted from state targets"
      unless checked.submitBinding.event.payloadKind == .none &&
          checked.keyBinding.event.payloadKind == .key &&
          checked.focusBinding.event.name == "focus" && checked.blurBinding.event.name == "blur" do
        throw <| IO.userError "validated form browser event capabilities changed"
  let span : SourceSpan := {
    file := "form.rxui"
    start := { line := 4, column := 1, byteOffset := 24 }
    stop := { line := 4, column := 5, byteOffset := 28 }
  }
  match (ValidatedFormSpec.create "" { name := "", age := "17", accepted := false } span).check with
  | .ok _ => throw <| IO.userError "empty validated form name was accepted"
  | .error error =>
      unless error.code == "LRX-ELAB-202" && error.spans == #[span] do
        throw <| IO.userError "empty validated form name diagnostic changed"

end LeanRxTest.Form.Validated
