import examples.FilterLab
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.FilterLabBuild

open LeanRx LeanRxExamples.FilterLab

def generateInto (directory : System.FilePath) : IO Unit := do
  match FilterLab_spec.check with
  | .error error =>
      throw <| IO.userError s!"Filter component invalid: {error.code}"
  | .ok checked => do
      let emitted ← match Backend.Component.emit "FilterLab.mjs" checked with
        | .ok emitted => pure emitted
        | .error error => throw <| IO.userError s!"Filter backend failed: {error.code}"
      let source ← match Js.Printer.module .readable emitted.module with
        | .ok source => pure source
        | .error error => throw <| IO.userError s!"Filter printer failed: {error.code}"
      IO.FS.createDirAll directory
      IO.FS.writeFile (directory / "FilterLab.mjs") source
      IO.FS.writeFile (directory / "FilterLab.mjs.manifest.json") emitted.manifest.json
      IO.FS.writeFile (directory / "Filter.graph.json") (checked.graph.toJson ++ "\n")
      IO.FS.writeFile (directory / "leanrx_dom.mjs")
        (← IO.FS.readFile "runtime/leanrx_dom.mjs")

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.FilterLabBuild
