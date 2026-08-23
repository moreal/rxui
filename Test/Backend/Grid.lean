import LeanRx.Backend.Grid

namespace LeanRxTest.Backend.Grid

open LeanRx LeanRx.Grid

private def assertEq [BEq α] [ToString α] (expected actual : α) : IO Unit :=
  unless expected == actual do
    throw <| IO.userError s!"expected {expected}, got {actual}"

def run : IO Unit := do
  let checked ← match (Spec.create "LeanRx 10k Data Grid").check with
    | .ok checked => pure checked
    | .error error => throw <| IO.userError error.code
  let emitted ← match Backend.Grid.emit "DataGrid.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"{error.code}: {error.message}"
  assertEq #["mountFull", "mountDelta", "mountHybrid"] emitted.manifest.exports
  assertEq 10000 checked.spec.rowCount
  assertEq 7 emitted.manifest.eventCount
  assertEq 14 emitted.manifest.runtimeAbi
  assertEq #["./leanrx_dom.mjs", "./leanrx_region.mjs", "./leanrx_delta_region.mjs"]
    emitted.manifest.hostImports
  unless emitted.manifest.features.contains "structural-delta" &&
      emitted.manifest.features.contains "hybrid-cost-model" do
    throw <| IO.userError "grid manifest lost structural strategy features"
  let readable ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError error.code
  let compact ← match Js.Printer.module .compact emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError error.code
  unless readable.contains "createDeltaKeyedRegion" && readable.contains "mountHybrid" &&
      readable.contains "10000" && readable.contains "table" && readable.contains "cell" &&
      compact.length < readable.length do
    throw <| IO.userError "grid printer output lost checked strategy lowering"

end LeanRxTest.Backend.Grid
