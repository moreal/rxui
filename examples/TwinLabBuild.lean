import examples.TwinLab
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.TwinLabBuild

open LeanRx LeanRxExamples.TwinLab

private def emitComponent (directory : System.FilePath) (moduleName graphName : String)
    (checked : CheckedComponent Γ) : IO Unit := do
  let emitted ← match Backend.Component.emit moduleName checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"Twin backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"Twin printer failed: {error.code}"
  IO.FS.writeFile (directory / moduleName) source
  IO.FS.writeFile (directory / s!"{moduleName}.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / graphName) (checked.graph.toJson ++ "\n")

def generateInto (directory : System.FilePath) : IO Unit := do
  match TwinLab_spec.check with
  | .error error => throw <| IO.userError s!"Twin component invalid: {error.code}"
  | .ok twin => do
      IO.FS.createDirAll directory
      emitComponent directory "TwinLab.mjs" "Twin.graph.json" twin
      IO.FS.writeFile (directory / "leanrx_dom.mjs")
        (← IO.FS.readFile "runtime/leanrx_dom.mjs")
      IO.FS.writeFile (directory / "leanrx_region.mjs")
        (← IO.FS.readFile "runtime/leanrx_region.mjs")

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.TwinLabBuild
