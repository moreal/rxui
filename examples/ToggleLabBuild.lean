import examples.ToggleLab
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.ToggleLabBuild

open LeanRx LeanRxExamples.ToggleLab

def generateInto (directory : System.FilePath) : IO Unit := do
  match ToggleLab_spec.check with
  | .error error =>
      throw <| IO.userError s!"Toggle component invalid: {error.code}"
  | .ok checked => do
      let emitted ← match Backend.Component.emit "ToggleLab.mjs" checked with
        | .ok emitted => pure emitted
        | .error error => throw <| IO.userError s!"Toggle backend failed: {error.code}"
      let source ← match Js.Printer.module .readable emitted.module with
        | .ok source => pure source
        | .error error => throw <| IO.userError s!"Toggle printer failed: {error.code}"
      IO.FS.createDirAll directory
      IO.FS.writeFile (directory / "ToggleLab.mjs") source
      IO.FS.writeFile (directory / "ToggleLab.mjs.manifest.json") emitted.manifest.json
      IO.FS.writeFile (directory / "Toggle.graph.json") (checked.graph.toJson ++ "\n")
      IO.FS.writeFile (directory / "leanrx_dom.mjs")
        (← IO.FS.readFile "runtime/leanrx_dom.mjs")
      IO.FS.writeFile (directory / "leanrx_form_events.mjs")
        (← IO.FS.readFile "runtime/leanrx_form_events.mjs")
      IO.FS.writeFile (directory / "leanrx_region.mjs")
        (← IO.FS.readFile "runtime/leanrx_region.mjs")

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.ToggleLabBuild
