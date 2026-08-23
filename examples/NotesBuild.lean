import examples.Notes
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.NotesBuild

open LeanRx LeanRx.Effect LeanRx.Notes LeanRxExamples.Notes

private def expectedJson : Except String String := do
  let restore := update initial .restore
  let (restoreHandle, key) ← match restore.command with
    | .storageGet handle key _ => .ok (handle, key)
    | _ => .error "Notes restore did not produce storageGet"
  let edited := update restore.state (.edit "expected")
  let (debounceHandle, delay) ← match edited.command with
    | .batch #[.cancel _, .none, .timeout handle delay _] => .ok (handle, delay)
    | _ => .error "Notes edit did not cancel restore and schedule timeout"
  let saving := update edited.state (.debounceFired debounceHandle)
  let saveHandle ← match saving.command with
    | .storageSet handle _ _ _ => .ok handle
    | _ => .error "Notes debounce did not produce storageSet"
  let saveFailed := update saving.state (.stored saveHandle (.error {
    code := "LRX-PORT-202", message := "quota exceeded"
  }))
  let restoreFailed := update restore.state (.restored restoreHandle (.error {
    code := "LRX-PORT-201", message := "restore broke"
  }))
  pure <| "{\"storageKey\":" ++ GraphSerialize.jsonString key ++
    ",\"debounceMs\":" ++ toString delay.toNat ++
    ",\"initialStatus\":" ++ GraphSerialize.jsonString (statusText initial) ++
    ",\"waitingStatus\":" ++ GraphSerialize.jsonString (statusText edited.state) ++
    ",\"saveFailureStatus\":" ++ GraphSerialize.jsonString (statusText saveFailed.state) ++
    ",\"restoreFailureStatus\":" ++
      GraphSerialize.jsonString (statusText restoreFailed.state) ++ "}\n"

private def generateChecked (directory : System.FilePath) (checked : Spec.Checked) : IO Unit := do
  let emitted ← match Backend.Notes.emit "Notes.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"Notes backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"Notes printer failed: {error.code}"
  let expected ← match expectedJson with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "Notes.mjs") source
  IO.FS.writeFile (directory / "Notes.mjs.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / "Notes.expected.json") expected
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")
  IO.FS.writeFile (directory / "leanrx_form_events.mjs")
    (← IO.FS.readFile "runtime/leanrx_form_events.mjs")
  IO.FS.writeFile (directory / "leanrx_effects.mjs") (← IO.FS.readFile "runtime/leanrx_effects.mjs")

def generateInto (directory : System.FilePath) : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"Notes component invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.NotesBuild
