import examples.Counter

namespace LeanRxExamples.CounterMain

open LeanRx LeanRxExamples.Counter

private def generateChecked (directory : System.FilePath)
    (checked : CheckedComponent CounterSchema) : IO Unit := do
  let emitted ← match Backend.Component.emit "Counter.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"Counter backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"Counter printer failed: {error.code}"
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "Counter.mjs") source
  IO.FS.writeFile (directory / "Counter.mjs.manifest.json") emitted.manifest
  IO.FS.writeFile (directory / "Counter.graph.json") checked.graph.toJson
  IO.FS.writeFile (directory / "Counter.graph.dot") checked.graph.toDot
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")
  IO.FS.writeFile (directory / "leanrx_host.mjs") (← IO.FS.readFile "runtime/leanrx_host.mjs")

def generate (directory : System.FilePath) : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"Counter component invalid: {error.code}"
  | .ok checked => generateChecked directory checked

end LeanRxExamples.CounterMain

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  match values with
  | directory :: _ => LeanRxExamples.CounterMain.generate ⟨directory⟩
  | [] => throw <| IO.userError "expected Counter output directory"
