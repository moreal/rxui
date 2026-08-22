import examples.DataGrid
import LeanRx.Cli.AtomicOutput
import LeanRx.Graph.Serialize

namespace LeanRxExamples.DataGridBuild

open LeanRx LeanRx.Grid LeanRxExamples.DataGrid

private def expectedJson (checked : Spec.Checked) : String :=
  let visible := visibleRows checked.finalState
  let firstId := visible.head?.map (·.id) |>.getD 0
  let lastId := visible.reverse.head?.map (·.id) |>.getD 0
  let rows := String.intercalate "," <| visible.map fun row =>
    "[" ++ toString row.id ++ "," ++
      GraphSerialize.jsonString s!"{row.label} value {row.value}" ++ "," ++
      (if row.selected then "true" else "false") ++ "]"
  "{\"sourceCount\":" ++ toString checked.finalState.rows.length ++
    ",\"visibleCount\":" ++ toString visible.length ++
    ",\"firstId\":" ++ toString firstId ++
    ",\"lastId\":" ++ toString lastId ++
    ",\"selected\":" ++ toString (checked.finalState.selected.getD 0) ++
    ",\"rows\":[" ++ rows ++ "]" ++
    ",\"operationCount\":" ++ toString checked.spec.operations.length ++
    ",\"strategies\":[\"full\",\"delta\",\"hybrid\"]}\n"

private def generateChecked (directory : System.FilePath) (checked : Spec.Checked) : IO Unit := do
  let emitted ← match Backend.Grid.emit "DataGrid.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"data-grid backend failed: {error.code}"
  let readable ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"data-grid printer failed: {error.code}"
  let compact ← match Js.Printer.module .compact emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"data-grid compact printer failed: {error.code}"
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "DataGrid.mjs") readable
  IO.FS.writeFile (directory / "DataGrid.min.mjs") compact
  IO.FS.writeFile (directory / "DataGrid.mjs.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / "DataGrid.expected.json") (expectedJson checked)
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")
  IO.FS.writeFile (directory / "leanrx_region.mjs") (← IO.FS.readFile "runtime/leanrx_region.mjs")
  IO.FS.writeFile (directory / "leanrx_delta_region.mjs")
    (← IO.FS.readFile "runtime/leanrx_delta_region.mjs")
  IO.FS.writeFile (directory / "leanrx_host.mjs") (← IO.FS.readFile "runtime/leanrx_host.mjs")

def generateInto (directory : System.FilePath) : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"data-grid component invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.DataGridBuild
