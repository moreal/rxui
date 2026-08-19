import examples.DiamondLab
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.DiamondLabBuild

open LeanRx LeanRxExamples.DiamondLab

private def generateExpected (directory : System.FilePath) : IO Unit := do
  let proofProgram ← match Graph.planInt intSpec with
    | .ok checked => pure checked
    | .error error => throw <| IO.userError s!"Diamond proof adapter failed: {error.code}"
  let initial := Abstract.Reference.initState proofProgram.program fun id =>
    if id = 0 then 1 else 0
  let reference := Abstract.Reference.run proofProgram.program initial abstractTransaction
  let optimized := Abstract.Optimized.run proofProgram.program initial abstractTransaction
  unless reference.store 3 == 19 && optimized.store 3 == 19 &&
      reference.observations == optimized.observations do
    throw <| IO.userError "Diamond reference/optimized semantics diverged"
  IO.FS.writeFile (directory / "Diamond.expected.json") <|
    "{\"initialTotal\":13,\"finalTotal\":" ++ toString (reference.store 3) ++
      ",\"derivedEvaluations\":" ++ toString optimized.derivedEvaluations ++
      ",\"sinkEvaluations\":" ++ toString optimized.sinkEvaluations ++ "}\n"

private def generateChecked (directory : System.FilePath)
    (checked : CheckedComponent DiamondSchema) : IO Unit := do
  let emitted ← match Backend.Component.emit "DiamondLab.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"Diamond backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"Diamond printer failed: {error.code}"
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "DiamondLab.mjs") source
  IO.FS.writeFile (directory / "DiamondLab.mjs.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / "Diamond.graph.json") (checked.graph.toJson ++ "\n")
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")
  IO.FS.writeFile (directory / "leanrx_host.mjs") (← IO.FS.readFile "runtime/leanrx_host.mjs")
  generateExpected directory

def generateInto (directory : System.FilePath) : IO Unit :=
  match DiamondSyntax_spec.check with
  | .error error => throw <| IO.userError s!"Diamond component invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.DiamondLabBuild
