import examples.Notes
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.NotesBuild

open LeanRx LeanRx.Effect LeanRx.Notes LeanRxExamples.Notes

private def expectedJson : Except String String := do
  let restore := update initial .restore
  let key ← match restore.command with
    | .storageGet _ key _ => .ok key
    | _ => .error "Notes restore did not produce storageGet"
  let edited := update restore.state (.edit "expected")
  let delay ← match edited.command with
    | .batch #[.cancel _, .none, .timeout _ delay _] => .ok delay
    | _ => .error "Notes edit did not cancel restore and schedule timeout"
  pure <| "{\"storageKey\":" ++ GraphSerialize.jsonString key ++
    ",\"debounceMs\":" ++ toString delay.toNat ++ "}\n"

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
  IO.FS.writeFile (directory / "leanrx_host.mjs") (← IO.FS.readFile "runtime/leanrx_host.mjs")
  IO.FS.writeFile (directory / "leanrx_effects.mjs") (← IO.FS.readFile "runtime/leanrx_effects.mjs")

def generateInto (directory : System.FilePath) : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"Notes component invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.NotesBuild
