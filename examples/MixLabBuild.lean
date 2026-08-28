import examples.MixLab
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.MixLabBuild

open LeanRx LeanRxExamples.MixLab

private def emitComponent (directory : System.FilePath) (moduleName graphName : String)
    (checked : CheckedComponent Γ) : IO Unit := do
  let emitted ← match Backend.Component.emit moduleName checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"Mix backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"Mix printer failed: {error.code}"
  IO.FS.writeFile (directory / moduleName) source
  IO.FS.writeFile (directory / s!"{moduleName}.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / graphName) (checked.graph.toJson ++ "\n")

def generateInto (directory : System.FilePath) : IO Unit := do
  match Badge_spec.check, MixLab_spec.check with
  | .error error, _ =>
      throw <| IO.userError s!"Badge component invalid: {error.code}"
  | _, .error error =>
      throw <| IO.userError s!"Mix component invalid: {error.code}"
  | .ok badge, .ok mix => do
      IO.FS.createDirAll directory
      emitComponent directory "Badge.mjs" "Badge.graph.json" badge
      emitComponent directory "MixLab.mjs" "Mix.graph.json" mix
      IO.FS.writeFile (directory / "leanrx_dom.mjs")
        (← IO.FS.readFile "runtime/leanrx_dom.mjs")
      IO.FS.writeFile (directory / "leanrx_region.mjs")
        (← IO.FS.readFile "runtime/leanrx_region.mjs")

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.MixLabBuild
