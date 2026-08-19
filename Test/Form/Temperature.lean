import LeanRx.Form.Temperature

namespace LeanRxTest.Form.Temperature

open LeanRx LeanRx.Form

def spec : TemperatureSpec := TemperatureSpec.create "Temperature Converter" "0" "32"

def run : IO Unit := do
  match spec.check with
  | .error error => throw <| IO.userError s!"temperature model failed: {error.code}"
  | .ok checked =>
      unless checked.graph.graph.nodes.map (·.name) ==
          #["celsius", "fahrenheit", "celsiusValue", "fahrenheitValue"] &&
          checked.graph.graph.nodes.map (·.rank) == #[0, 0, 1, 1] do
        throw <| IO.userError "temperature graph gained a cycle or unstable shape"
      unless checked.celsiusEvent.payloadType == .string &&
          checked.celsiusEvent.target.index == 0 &&
          checked.fahrenheitEvent.payloadType == .string &&
          checked.fahrenheitEvent.target.index == 1 do
        throw <| IO.userError "temperature input payloads drifted from string state targets"
  match (TemperatureSpec.create "Bad" "0" "31").check with
  | .ok _ => throw <| IO.userError "inconsistent initial temperatures were accepted"
  | .error error =>
      unless error.code == "LRX-TYPE-206" do
        throw <| IO.userError "initial temperature mismatch returned the wrong diagnostic"

end LeanRxTest.Form.Temperature
