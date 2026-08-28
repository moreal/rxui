import examples.NestLab
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.NestLabBuild

open LeanRx LeanRxExamples.NestLab

private def emitComponent (directory : System.FilePath) (moduleName graphName : String)
    (checked : CheckedComponent Γ) : IO Unit := do
  let emitted ← match Backend.Component.emit moduleName checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"Nest backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"Nest printer failed: {error.code}"
  IO.FS.writeFile (directory / moduleName) source
  IO.FS.writeFile (directory / s!"{moduleName}.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / graphName) (checked.graph.toJson ++ "\n")

def generateInto (directory : System.FilePath) : IO Unit := do
  match Tick_spec.check, Pulse_spec.check, NestLab_spec.check with
  | .error error, _, _ =>
      throw <| IO.userError s!"Tick component invalid: {error.code}"
  | _, .error error, _ =>
      throw <| IO.userError s!"Pulse component invalid: {error.code}"
  | _, _, .error error =>
      throw <| IO.userError s!"Nest component invalid: {error.code}"
  | .ok tick, .ok pulse, .ok nest => do
      IO.FS.createDirAll directory
      emitComponent directory "Tick.mjs" "Tick.graph.json" tick
      emitComponent directory "Pulse.mjs" "Pulse.graph.json" pulse
      emitComponent directory "NestLab.mjs" "Nest.graph.json" nest
      IO.FS.writeFile (directory / "leanrx_dom.mjs")
        (← IO.FS.readFile "runtime/leanrx_dom.mjs")
      IO.FS.writeFile (directory / "leanrx_region.mjs")
        (← IO.FS.readFile "runtime/leanrx_region.mjs")

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.NestLabBuild
