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

private def itemJson (item : Item) : String :=
  "{\"id\":" ++ toString item.id ++
    ",\"title\":" ++ Js.Printer.stringLiteral item.title ++
    ",\"completed\":" ++ (if item.completed then "true" else "false") ++ "}"

private def expectedJson : String :=
  let state := scenario
  "{\"rows\":[" ++ String.intercalate "," (state.todos.map itemJson) ++
    "],\"remaining\":" ++ toString (remaining state) ++
    ",\"filter\":" ++ Js.Printer.stringLiteral state.filter.slug ++ "}\n"

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
  IO.FS.writeFile (directory / "leanrx_region.mjs") (← IO.FS.readFile "runtime/leanrx_region.mjs")
  IO.FS.writeFile (directory / "leanrx_host.mjs") (← IO.FS.readFile "runtime/leanrx_host.mjs")

def generateInto (directory : System.FilePath) : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"TodoMVC component invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.TodoMVCBuild
