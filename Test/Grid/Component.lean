import LeanRx.Grid.Component

namespace LeanRxTest.Grid.Component

open LeanRx.Grid

private def assertEq [BEq α] [ToString α] (expected actual : α) : IO Unit :=
  unless expected == actual do
    throw <| IO.userError s!"expected {expected}, got {actual}"

private def expectError (code : String) : Except Error α → IO Unit
  | .ok _ => throw <| IO.userError s!"expected {code}, got success"
  | .error error => assertEq code error.code

def run : IO Unit := do
  let spec := Spec.create "LeanRx 10k Data Grid"
  let checked ← match spec.check with
    | .ok checked => pure checked
    | .error error => throw <| IO.userError s!"unexpected {error.code}"
  assertEq 7 spec.operations.length
  assertEq 9000 checked.finalState.rows.length
  assertEq 5000 (visibleRows checked.finalState).length
  assertEq (some 7777) checked.finalState.selected
  expectError "LRX-ELAB-301" (Spec.create "" |>.check)
  expectError "LRX-TYPE-301" (Spec.create "wrong-size" 9999 |>.check)
  expectError "LRX-TYPE-302" (Spec.create "same-swap" (swapSecond := 1) |>.check)
  expectError "LRX-GRID-004" (Spec.create "bad-remove" (removeDivisor := 0) |>.check)
  expectError "LRX-GRID-005" (Spec.create "bad-swap" (swapSecond := 10001) |>.check)
  expectError "LRX-GRID-006" (Spec.create "bad-select" (selectId := 10001) |>.check)

end LeanRxTest.Grid.Component
