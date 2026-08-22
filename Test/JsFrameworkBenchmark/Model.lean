import LeanRx.JsFrameworkBenchmark.Model

namespace LeanRxTest.JsFrameworkBenchmark.Model

open LeanRx.JsFrameworkBenchmark

private def assertEq [BEq α] [ToString α] (expected actual : α) : IO Unit :=
  unless expected == actual do
    throw <| IO.userError s!"expected {expected}, got {actual}"

def run : IO Unit := do
  let spec := Spec.create "LeanRx-\"keyed\""
  let checked ← match spec.check with
    | .ok checked => pure checked
    | .error error => throw <| IO.userError error.code
  assertEq 1 checked.initial.nextId
  let added := update spec checked.initial .add
  assertEq 1000 added.rows.length
  assertEq (some 1) (added.rows[0]?.map (·.id))
  assertEq (some 1000) (added.rows[999]?.map (·.id))
  assertEq (some "Row 1") (added.rows[0]?.map (·.label))
  assertEq 1001 added.nextId

  let missingSelection := update spec added (.select 1001)
  assertEq none missingSelection.selected
  assertEq 1000 missingSelection.rows.length

  let swapped := update spec added .swapRows
  assertEq (some 999) (swapped.rows[1]?.map (·.id))
  assertEq (some 2) (swapped.rows[998]?.map (·.id))
  let changed := update spec swapped .update
  assertEq true (changed.rows[0]?.map (·.label.endsWith " !!!") |>.getD false)
  assertEq false (changed.rows[1]?.map (·.label.endsWith " !!!") |>.getD true)
  assertEq true (changed.rows[10]?.map (·.label.endsWith " !!!") |>.getD false)
  let changedTwice := update spec changed .update
  assertEq (some "Row 1 !!! !!!") (changedTwice.rows[0]?.map (·.label))

  let selected := update spec changed (.select 999)
  assertEq (some 999) selected.selected

  let selectedAndUpdated := update spec selected .update
  assertEq (some 999) selectedAndUpdated.selected
  let selectedAndAdded := update spec selectedAndUpdated .add
  assertEq (some 999) selectedAndAdded.selected
  assertEq 2000 selectedAndAdded.rows.length
  assertEq (some 1001) (selectedAndAdded.rows[1000]?.map (·.id))
  assertEq 2001 selectedAndAdded.nextId
  let selectedAndSwapped := update spec selectedAndAdded .swapRows
  assertEq (some 999) selectedAndSwapped.selected
  let missingDelete := update spec selectedAndSwapped (.delete 12001)
  assertEq 2000 missingDelete.rows.length
  assertEq (some 999) missingDelete.selected
  let otherDelete := update spec missingDelete (.delete 1)
  assertEq 1999 otherDelete.rows.length
  assertEq (some 999) otherDelete.selected

  let deleted := update spec selected (.delete 999)
  assertEq 999 deleted.rows.length
  assertEq none deleted.selected
  let replaced := update spec deleted .run
  assertEq (some 1001) (replaced.rows[0]?.map (·.id))
  assertEq (some 2000) (replaced.rows[999]?.map (·.id))
  let large := update spec replaced .runLots
  assertEq 10000 large.rows.length
  assertEq (some 2001) (large.rows[0]?.map (·.id))
  assertEq (some 12000) (large.rows[9999]?.map (·.id))
  let selectedLarge := update spec large (.select 2001)
  let cleared := update spec selectedLarge .clear
  assertEq 0 cleared.rows.length
  assertEq none cleared.selected
  assertEq 12001 cleared.nextId
  let afterClear := update spec cleared .add
  assertEq (some 12001) (afterClear.rows[0]?.map (·.id))

  let short := appendRows initial 998
  let shortSwap := swapAt short 1 998
  assertEq 998 shortSwap.rows.length
  assertEq (some 2) (shortSwap.rows[1]?.map (·.id))
  assertEq 999 shortSwap.nextId

  let selectedForReplace := select added 5
  assertEq none (replaceRows selectedForReplace 3).selected
  assertEq (some 1001) ((replaceRows selectedForReplace 3).rows[0]?.map (·.id))

  match (Spec.create "").check with
  | .error error => assertEq "LRX-REGION-301" error.code
  | .ok _ => throw <| IO.userError "empty benchmark name unexpectedly passed"

end LeanRxTest.JsFrameworkBenchmark.Model
