import examples.BranchLab
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.BranchLabBuild

open LeanRx LeanRxExamples.BranchLab

def generateInto (directory : System.FilePath) : IO Unit := do
  match BranchLab_spec.check with
  | .error error =>
      throw <| IO.userError s!"Branch component invalid: {error.code}"
  | .ok checked => do
      let emitted ← match Backend.Component.emit "BranchLab.mjs" checked with
        | .ok emitted => pure emitted
        | .error error => throw <| IO.userError s!"Branch backend failed: {error.code}"
      let source ← match Js.Printer.module .readable emitted.module with
        | .ok source => pure source
        | .error error => throw <| IO.userError s!"Branch printer failed: {error.code}"
      IO.FS.createDirAll directory
      IO.FS.writeFile (directory / "BranchLab.mjs") source
      IO.FS.writeFile (directory / "BranchLab.mjs.manifest.json") emitted.manifest.json
      IO.FS.writeFile (directory / "Branch.graph.json") (checked.graph.toJson ++ "\n")
      IO.FS.writeFile (directory / "leanrx_dom.mjs")
        (← IO.FS.readFile "runtime/leanrx_dom.mjs")
      IO.FS.writeFile (directory / "leanrx_region.mjs")
        (← IO.FS.readFile "runtime/leanrx_region.mjs")

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.BranchLabBuild
