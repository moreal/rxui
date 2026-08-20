import LeanRx.Grid.Model

namespace LeanRxTest.Grid.Model

open LeanRx.Grid LeanRx.Collection

private def assertEq [BEq α] [ToString α] (expected actual : α) : IO Unit :=
  unless expected == actual do
    throw <| IO.userError s!"expected {expected}, got {actual}"

private def assertBEq [BEq α] (label : String) (expected actual : α) : IO Unit :=
  unless expected == actual do
    throw <| IO.userError s!"{label} mismatch"

private def expectOk : Except LeanRx.Grid.Error α → IO α
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"unexpected {error.code}: {error.message}"

private def expectError (code : String) (path : List String) :
    Except LeanRx.Grid.Error α → IO Unit
  | .ok _ => throw <| IO.userError s!"expected {code}, got success"
  | .error error => do
      assertEq code error.code
      assertBEq s!"{code} path" path error.path

def run : IO Unit := do
  let created ← expectOk <| update empty (.createRows 10000)
  assertEq 10000 created.rows.length
  assertEq (some 5000) (created.rows[5000]?.map (·.id))
  let updated ← expectOk <| update created (.updateOne 5000)
  assertEq (some 50001) (updated.rows[5000]?.map (·.value))
  let updatePlan := plannedDeltas created (.updateOne 5000) updated
  assertEq false updatePlan.usedReset
  assertEq 1 updatePlan.deltas.length
  let removed ← expectOk <| update updated (.removeEvery 10)
  assertEq 9000 removed.rows.length
  let removalPlan := plannedDeltas updated (.removeEvery 10) removed
  assertEq false removalPlan.usedReset
  assertEq 1000 removalPlan.deltas.length
  let swapped ← expectOk <| update removed (.swap 1 9998)
  let swapPlan := plannedDeltas removed (.swap 1 9998) swapped
  assertEq false swapPlan.usedReset
  assertEq 2 swapPlan.deltas.length
  let filtered ← expectOk <| update swapped (.setFilter .odd)
  assertEq 5000 (visibleRows filtered).length
  let filterPlan := plannedDeltas swapped (.setFilter .odd) filtered
  assertEq true filterPlan.usedReset
  let sorted ← expectOk <| update filtered (.setSort .descending)
  assertEq (some 9999) ((visibleRows sorted).head?.map (·.id))
  let selected ← expectOk <| update sorted (.select 7777)
  assertEq (some true) ((visibleRows selected).find? (fun row => row.id == 7777) |>.map (·.selected))
  let selectedPlan := plannedDeltas sorted (.select 7777) selected
  assertEq false selectedPlan.usedReset
  assertEq 1 selectedPlan.deltas.length
  for strategy in [Strategy.full, .delta, .hybrid] do
    let result ← expectOk <| runTrace strategy
    assertEq 9000 result.finalState.rows.length
    assertEq 5000 (visibleRows result.finalState).length
    assertEq (some 7777) result.finalState.selected
  let full ← expectOk <| runTrace .full
  let delta ← expectOk <| runTrace .delta
  let hybrid ← expectOk <| runTrace .hybrid
  assertBEq "full/delta logical rows" (visibleRows full.finalState) (visibleRows delta.finalState)
  assertBEq "full/hybrid logical rows" (visibleRows full.finalState) (visibleRows hybrid.finalState)
  assertEq 7 (full.modes.filter (· == .keyedFull)).length
  assertEq true (delta.work.deltaEdits > 0)
  assertEq true (hybrid.modes.contains .deltaBatch)
  assertEq true (hybrid.modes.contains .keyedFull)
  expectError "LRX-GRID-001" ["rows"] (update empty (.createRows 0))
  expectError "LRX-GRID-002" ["rows"] (update empty (.createRows 100001))
  expectError "LRX-GRID-003" ["row:10001"] (update created (.updateOne 10001))
  expectError "LRX-GRID-004" ["removeEvery"] (update created (.removeEvery 0))
  expectError "LRX-GRID-005" ["row:1", "row:10001"]
    (update created (.swap 1 10001))
  expectError "LRX-GRID-006" ["row:10001"] (update created (.select 10001))

end LeanRxTest.Grid.Model
