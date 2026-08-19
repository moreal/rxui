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
      unless checked.nameEvent.payloadType == .string && checked.nameEvent.target.index == 0 &&
          checked.ageEvent.payloadType == .string && checked.ageEvent.target.index == 1 &&
          checked.acceptedEvent.payloadType == .bool && checked.acceptedEvent.target.index == 2 do
        throw <| IO.userError "validated form typed payloads drifted from state targets"
      unless checked.submitBinding.event.payloadKind == .none &&
          checked.keyBinding.event.payloadKind == .key &&
          checked.focusBinding.event.name == "focus" && checked.blurBinding.event.name == "blur" do
        throw <| IO.userError "validated form browser event capabilities changed"

end LeanRxTest.Form.Validated
