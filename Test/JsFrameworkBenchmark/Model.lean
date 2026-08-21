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
  let swapped := update spec added .swapRows
  assertEq (some 999) (swapped.rows[1]?.map (·.id))
  assertEq (some 2) (swapped.rows[998]?.map (·.id))
  let changed := update spec swapped .update
  assertEq true (changed.rows[0]?.map (·.label.endsWith " !!!") |>.getD false)
  assertEq false (changed.rows[1]?.map (·.label.endsWith " !!!") |>.getD true)
  let selected := update spec changed (.select 999)
  assertEq (some 999) selected.selected
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
  assertEq 0 (update spec large .clear).rows.length
  match (Spec.create "").check with
  | .error error => assertEq "LRX-REGION-301" error.code
  | .ok _ => throw <| IO.userError "empty benchmark name unexpectedly passed"

end LeanRxTest.JsFrameworkBenchmark.Model
