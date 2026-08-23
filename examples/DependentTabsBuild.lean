import examples.DependentTabs
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.DependentTabsBuild

open LeanRx LeanRxExamples.DependentTabs

private def generateChecked (directory : System.FilePath)
    (checked : TabsSpec.Checked 2) : IO Unit := do
  let emitted ← match Backend.Tabs.emit "DependentTabs.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"Dependent Tabs backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"Dependent Tabs printer failed: {error.code}"
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "DependentTabs.mjs") source
  IO.FS.writeFile (directory / "DependentTabs.mjs.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / "DependentTabs.graph.json") (checked.graph.toJson ++ "\n")
  IO.FS.writeFile (directory / "DependentTabs.graph.dot") (checked.graph.toDot ++ "\n")
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")

def generateInto (directory : System.FilePath) : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"Dependent Tabs invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.DependentTabsBuild
