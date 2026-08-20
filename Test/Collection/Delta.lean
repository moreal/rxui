import LeanRx.Collection.Delta

namespace LeanRxTest.Collection.Delta

open LeanRx.Collection

private def assertEq [BEq α] [ToString α] (expected actual : α) : IO Unit :=
  unless expected == actual do
    throw <| IO.userError s!"expected {expected}, got {actual}"

private def assertOk [BEq α] [ToString α] (expected : α) : Except Error α → IO Unit
  | .ok actual => assertEq expected actual
  | .error error => throw <| IO.userError s!"unexpected {error.code}"

private def assertError (code : String) (index size : Nat) : Except Error α → IO Unit
  | .ok _ => throw <| IO.userError s!"expected {code}, got success"
  | .error error => do
      assertEq code error.code
      assertEq index error.index
      assertEq size error.size

def run : IO Unit := do
  assertOk [0, 3, 2] <|
    ListDelta.applyAll [.insert 0 0, .update 2 2, .move 3 1, .remove 2] [1, 9, 3]
  let exact := PlannedDeltas.create [1, 2, 3] [1, 8, 3] [.update 1 8]
  assertEq false exact.usedReset
  assertOk [1, 8, 3] (ListDelta.applyAll exact.deltas [1, 2, 3])
  let fallback := PlannedDeltas.create [1, 2, 3] [1, 8, 3] [.remove 0]
  assertEq true fallback.usedReset
  assertOk [1, 8, 3] (ListDelta.applyAll fallback.deltas [1, 2, 3])
  assertError "LRX-DELTA-001" 4 3 ((ListDelta.insert 4 9).apply [1, 2, 3])
  assertError "LRX-DELTA-002" 3 3 ((ListDelta.remove 3).apply [1, 2, 3])
  assertError "LRX-DELTA-003" 3 3 ((ListDelta.update 3 9).apply [1, 2, 3])
  assertError "LRX-DELTA-004" 3 3 ((ListDelta.move 3 0).apply [1, 2, 3])
  assertError "LRX-DELTA-005" 3 2 ((ListDelta.move 0 3).apply [1, 2, 3])
  assertOk [1, 2, 4, 3] ((ListDelta.insert 3 3).apply [1, 2, 4])
  assertOk [2, 3, 1] ((ListDelta.move 0 2).apply [1, 2, 3])
  assertError "LRX-DELTA-002" 0 0 ((ListDelta.remove 0).apply ([] : List Nat))
  assertError "LRX-DELTA-003" 0 0 ((ListDelta.update 0 1).apply ([] : List Nat))
  assertError "LRX-DELTA-004" 0 0 ((ListDelta.move 0 0).apply ([] : List Nat))
  assertError "LRX-DELTA-002" 3 3 <|
    ListDelta.applyAll [.remove 3, .insert 0 9] [1, 2, 3]
  let resetThenUpdate := PlannedDeltas.create [0] [2]
    [.reset #[1], .update 0 2]
  assertEq true resetThenUpdate.usedReset
  assertOk [2] (ListDelta.applyAll resetThenUpdate.deltas [0])

end LeanRxTest.Collection.Delta
