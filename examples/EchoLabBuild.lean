import examples.EchoLab
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.EchoLabBuild

open LeanRx LeanRxExamples.EchoLab

private def generateChecked (directory : System.FilePath)
    (checked : CheckedComponent EchoSchema) : IO Unit := do
  let emitted ← match Backend.Component.emit "EchoLab.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"Echo backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"Echo printer failed: {error.code}"
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "EchoLab.mjs") source
  IO.FS.writeFile (directory / "EchoLab.mjs.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / "Echo.graph.json") (checked.graph.toJson ++ "\n")
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")
  IO.FS.writeFile (directory / "leanrx_form_events.mjs")
    (← IO.FS.readFile "runtime/leanrx_form_events.mjs")

def generateInto (directory : System.FilePath) : IO Unit :=
  match EchoLab_spec.check with
  | .error error => throw <| IO.userError s!"Echo component invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.EchoLabBuild
