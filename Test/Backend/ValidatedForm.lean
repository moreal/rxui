import LeanRx.Backend.ValidatedForm
import LeanRx.Backend.JsPrinter
import Test.Form.Validated

namespace LeanRxTest.Backend.ValidatedForm

open LeanRx LeanRx.Form LeanRxTest.Form.Validated

def run : IO Unit := do
  match spec.check with
  | .error error => throw <| IO.userError s!"validated form model failed: {error.code}"
  | .ok checked =>
    match Backend.ValidatedForm.emit "ValidatedForm.mjs" checked with
    | .error error => throw <| IO.userError s!"validated form backend failed: {error.code}"
    | .ok emitted =>
      let source ← match Js.Printer.module .readable emitted.module with
        | .ok source => pure source
        | .error error => throw <| IO.userError s!"validated form printer failed: {error.code}"
      unless source.contains "/^[0-9]+$/[\"test\"](state[1])" &&
          source.contains "listenValue(nameInput, \"input\"" &&
          source.contains "listenValue(ageInput, \"input\"" &&
          source.contains "listenValue(ageInput, \"change\"" &&
          source.contains "listenSubmit" && source.contains "listenChecked" &&
          source.contains "setProperty(submitButton, \"disabled\"" &&
          source.contains "command:fakeSubmit" && ¬source.contains "innerHTML" do
        throw <| IO.userError s!"validated form lowering changed:\n{source}"
      unless emitted.manifest.stateSlots ==
          #[RuntimeTypeId.string, RuntimeTypeId.string, RuntimeTypeId.bool] &&
          emitted.manifest.derivedCount == 0 && emitted.manifest.textSinkCount == 4 &&
          emitted.manifest.eventCount == 8 do
        throw <| IO.userError "validated form manifest changed"

end LeanRxTest.Backend.ValidatedForm
