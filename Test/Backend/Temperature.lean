import LeanRx.Backend.Temperature
import LeanRx.Backend.JsPrinter
import Test.Form.Temperature

namespace LeanRxTest.Backend.Temperature

open LeanRx LeanRx.Form LeanRxTest.Form.Temperature

def run : IO Unit := do
  match spec.check with
  | .error error => throw <| IO.userError s!"temperature model failed: {error.code}"
  | .ok checked =>
    match Backend.Temperature.emit "Temperature.mjs" checked with
    | .error error => throw <| IO.userError s!"temperature backend failed: {error.code}"
    | .ok emitted =>
      let source ← match Js.Printer.module .readable emitted.module with
        | .ok source => pure source
        | .error error => throw <| IO.userError s!"temperature printer failed: {error.code}"
      unless source.contains "/^-?[0-9]+$/[\"test\"](value)" &&
          source.contains "BigInt(value)" && source.contains "listenValue" &&
          source.contains "setProperty(context[1], \"value\", next)" &&
          ¬source.contains "eval(" && ¬source.contains "Function(" do
        throw <| IO.userError s!"temperature lowering changed:\n{source}"
      unless emitted.manifest.stateSlots == #[RuntimeTypeId.string, RuntimeTypeId.string] &&
          emitted.manifest.eventCount == 2 && emitted.manifest.runtimeAbi == LeanRx.runtimeAbi do
        throw <| IO.userError "temperature manifest changed"

end LeanRxTest.Backend.Temperature
