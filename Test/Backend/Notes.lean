import LeanRx.Backend.Notes
import LeanRx.Backend.JsPrinter

namespace LeanRxTest.Backend.Notes

open LeanRx LeanRx.Notes

private def assertTrue (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  let checked ← match (Spec.create "Notes").check with
    | .ok checked => pure checked
    | .error error => throw <| IO.userError error.message
  let emitted ← match Backend.Notes.emit "Notes.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"{error.code}: {error.message}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"{error.code}: {error.message}"
  assertTrue (source.contains "createEffectRuntime" &&
    source.contains "storageGet" && source.contains "storageSet" &&
    source.contains "timeout" && source.contains "makeEffectDisposer")
    "Notes backend omitted its checked command lifecycle"
  assertTrue (emitted.manifest.sourceCount == 1 && emitted.manifest.eventCount == 1 &&
    emitted.manifest.hostImports ==
      #["./leanrx_dom.mjs", "./leanrx_form_events.mjs", "./leanrx_effects.mjs"])
    "Notes manifest drifted"

end LeanRxTest.Backend.Notes
