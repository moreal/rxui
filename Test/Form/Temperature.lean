import LeanRx.Form.Temperature

namespace LeanRxTest.Form.Temperature

open LeanRx LeanRx.Form

def spec : TemperatureSpec := TemperatureSpec.create "Temperature Converter" "0" "32"

def run : IO Unit := do
  match spec.check with
  | .error error => throw <| IO.userError s!"temperature model failed: {error.code}"
  | .ok checked =>
      unless checked.graph.graph.nodes.map (·.name) ==
          #["celsius", "fahrenheit", "celsiusValue", "fahrenheitValue",
            "temperatureError", "celsiusInvalid", "fahrenheitInvalid"] &&
          checked.graph.graph.nodes.map (·.rank) == #[0, 0, 1, 1, 1, 1, 1] do
        throw <| IO.userError "temperature graph gained a cycle or unstable shape"
      unless checked.celsiusUpdate.binding.payloadType == .string &&
          checked.celsiusUpdate.binding.event.name == "input" &&
          checked.celsiusUpdate.writeTargetIndices == #[0, 1] &&
          checked.fahrenheitUpdate.binding.payloadType == .string &&
          checked.fahrenheitUpdate.binding.event.name == "input" &&
          checked.fahrenheitUpdate.writeTargetIndices == #[1, 0] do
        throw <| IO.userError "temperature input payloads drifted from string state targets"
  match (TemperatureSpec.create "Bad" "0" "31").check with
  | .ok _ => throw <| IO.userError "inconsistent initial temperatures were accepted"
  | .error error =>
      unless error.code == "LRX-TYPE-206" do
        throw <| IO.userError "initial temperature mismatch returned the wrong diagnostic"
  let span : SourceSpan := {
    file := "temperature.rxui"
    start := { line := 3, column := 2, byteOffset := 17 }
    stop := { line := 3, column := 8, byteOffset := 23 }
  }
  match (TemperatureSpec.create "" "0" "32" span).check with
  | .ok _ => throw <| IO.userError "empty temperature component name was accepted"
  | .error error =>
      unless error.code == "LRX-ELAB-201" && error.spans == #[span] do
        throw <| IO.userError "empty temperature name diagnostic changed"
  match (TemperatureSpec.create "Bad" "1_0" "50" span).check with
  | .ok _ => throw <| IO.userError "invalid initial temperature was accepted"
  | .error error =>
      unless error.code == "LRX-TYPE-201" && error.path == #["celsius"] &&
          error.spans == #[span] do
        throw <| IO.userError "invalid initial temperature diagnostic changed"

end LeanRxTest.Form.Temperature
