import LeanRx.Grid.Model

namespace LeanRx.Grid

/-- Public checked configuration for the M10 data-grid experiment. The
specialized backend consumes only `Checked`, so generated constants and the
native oracle cannot silently drift. -/
structure Spec where
  private mk ::
  name : String
  rowCount : Nat
  updateId : Nat
  removeDivisor : Nat
  swapFirst : Nat
  swapSecond : Nat
  selectId : Nat
  costModel : CostModel
deriving Repr

namespace Spec

def create (name : String) (rowCount : Nat := 10000) (updateId : Nat := 5000)
    (removeDivisor : Nat := 10) (swapFirst : Nat := 1) (swapSecond : Nat := 9998)
    (selectId : Nat := 7777) (costModel : CostModel := defaultCostModel) : Spec :=
  ⟨name, rowCount, updateId, removeDivisor, swapFirst, swapSecond, selectId, costModel⟩

def operations (spec : Spec) : List Operation := [
  .createRows spec.rowCount,
  .updateOne spec.updateId,
  .removeEvery spec.removeDivisor,
  .swap spec.swapFirst spec.swapSecond,
  .setFilter .odd,
  .setSort .descending,
  .select spec.selectId
]

structure Checked where
  private mk ::
  spec : Spec
  initial : State
  finalState : State
deriving Repr

private def runOperations (state : State) : List Operation → Except Error State
  | [] => .ok state
  | operation :: rest => do
      runOperations (← update state operation) rest

def check (spec : Spec) : Except Error Checked := do
  if spec.name.isEmpty then throw {
    code := "LRX-ELAB-301"
    message := "data-grid component name must not be empty"
    path := ["component"]
  }
  if spec.rowCount != 10000 then throw {
    code := "LRX-TYPE-301"
    message := "the M10 data-grid experiment requires exactly 10000 source rows"
    path := ["rows"]
  }
  if spec.costModel.maxDeltaEdits == 0 || spec.costModel.fullRowCost == 0 then throw {
    code := "LRX-TYPE-302"
    message := "hybrid cost parameters must have positive edit and full-row bounds"
    path := ["costModel"]
  }
  let finalState ← runOperations empty spec.operations
  pure ⟨spec, empty, finalState⟩

end Spec

end LeanRx.Grid
