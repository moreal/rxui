import examples.TodoMVC
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.TodoMVCBuild

open LeanRx LeanRx.Todo LeanRxExamples.TodoMVC

private def scenario : State :=
  let first := update (update initial
    (.setNewTitle "<img src=x onerror=\"globalThis.todoXss=true\">")) .add
  let second := update (update first (.setNewTitle "Second")) .add
  let toggled := update second (.toggle 0)
  let editing := update (update toggled (.startEditing 1)) (.setDraft " Edited ")
  update (update editing .commitEditing) .reverse

private def attributesJson (attributes : List (String × String)) : String :=
  "[" ++ String.intercalate "," (attributes.map fun (name, value) =>
    "[" ++ GraphSerialize.jsonString name ++ "," ++ GraphSerialize.jsonString value ++ "]") ++
    "]"

private def logicalJson : Region.LogicalNode → String
  | .text value =>
      "{\"kind\":\"text\",\"value\":" ++ GraphSerialize.jsonString value ++ "}"
  | .element tag attributes children =>
      "{\"kind\":\"element\",\"tag\":" ++ GraphSerialize.jsonString tag ++
        ",\"attributes\":" ++ attributesJson attributes ++
        ",\"children\":[" ++ String.intercalate "," (children.map logicalJson) ++ "]}"

/- The golden logical projection is generated from the JSX view surface in
`examples/TodoMVC.lean`; native tests pin it equal to `Todo.logical`. -/
private def expectedJson : String :=
  "{\"logical\":" ++ logicalJson (todoView spec.name scenario) ++ "}\n"

private def generateChecked (directory : System.FilePath) (checked : Spec.Checked) : IO Unit := do
  let emitted ← match Backend.Todo.emit "TodoMVC.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"TodoMVC backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"TodoMVC printer failed: {error.code}"
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "TodoMVC.mjs") source
  IO.FS.writeFile (directory / "TodoMVC.mjs.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / "TodoMVC.expected.json") expectedJson
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")
  IO.FS.writeFile (directory / "leanrx_form_events.mjs")
    (← IO.FS.readFile "runtime/leanrx_form_events.mjs")
  IO.FS.writeFile (directory / "leanrx_region.mjs") (← IO.FS.readFile "runtime/leanrx_region.mjs")
  IO.FS.writeFile (directory / "leanrx_unkeyed_region.mjs")
    (← IO.FS.readFile "runtime/leanrx_unkeyed_region.mjs")

def generateInto (directory : System.FilePath) : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"TodoMVC component invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.TodoMVCBuild
