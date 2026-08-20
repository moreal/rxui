import LeanRx

namespace LeanRxBench.DataGrid

open LeanRx.Grid

private def runChecked (strategy : Strategy) : IO TraceResult :=
  match runTrace strategy with
  | .ok result => pure result
  | .error error =>
      throw <| IO.userError s!"data-grid benchmark failed: {error.code}: {error.message}"

private def strategyName : Strategy → String
  | .full => "full"
  | .delta => "delta"
  | .hybrid => "hybrid"

private def countDeltaModes (modes : List PlanMode) : Nat :=
  modes.count .deltaBatch

private def printMeasurement (iterations : Nat) (strategy : Strategy)
    (baseline : TraceResult) : IO Unit := do
  let start ← IO.monoNanosNow
  for _ in List.range iterations do
    let result ← runChecked strategy
    unless result.finalState == baseline.finalState && result.work == baseline.work do
      throw <| IO.userError "data-grid benchmark became nondeterministic"
  let elapsed ← IO.monoNanosNow
  IO.println <| s!"data-grid strategy={strategyName strategy} iterations={iterations} " ++
    s!"allocations={baseline.work.collectionAllocations} " ++
    s!"derived={baseline.work.derivedEvaluations} " ++
    s!"regionVisits={baseline.work.regionVisits} " ++
    s!"deltaEdits={baseline.work.deltaEdits} " ++
    s!"deltaModes={countDeltaModes baseline.modes} resets={baseline.resetCount} " ++
    s!"elapsedNs={elapsed - start}"

def run (iterations : Nat) : IO Unit := do
  if iterations == 0 then
    throw <| IO.userError "data-grid benchmark iterations must be positive"
  let full ← runChecked .full
  let delta ← runChecked .delta
  let hybrid ← runChecked .hybrid
  unless full.finalState == delta.finalState && delta.finalState == hybrid.finalState do
    throw <| IO.userError "data-grid strategy correctness baseline failed"
  let visible := visibleRows full.finalState
  unless visible.length == 5000 && visible.head?.map (·.id) == some 9999 &&
      visible.getLast?.map (·.id) == some 1 && full.finalState.selected == some 7777 do
    throw <| IO.userError "data-grid defining observation changed"
  printMeasurement iterations .full full
  printMeasurement iterations .delta delta
  printMeasurement iterations .hybrid hybrid

end LeanRxBench.DataGrid

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  let iterations ← match values with
    | value :: _ => match value.toNat? with
      | some iterations => pure iterations
      | none => throw <| IO.userError "benchmark iterations must be a natural number"
    | [] => pure 20
  LeanRxBench.DataGrid.run iterations
