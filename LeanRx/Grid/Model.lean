import LeanRx.Collection.Delta

namespace LeanRx.Grid

open LeanRx.Collection

structure Row where
  id : Nat
  label : String
  value : Nat
  selected : Bool := false
deriving Repr, BEq, DecidableEq

namespace Row

def create (id : Nat) : Row := {
  id
  label := s!"Row {id}"
  value := id * 10
}

end Row

inductive Filter where
  | all
  | odd
deriving Repr, BEq, DecidableEq

inductive SortOrder where
  | source
  | descending
deriving Repr, BEq, DecidableEq

structure State where
  private mk ::
  rows : List Row
  filter : Filter := .all
  sortOrder : SortOrder := .source
  selected : Option Nat := none
deriving Repr, BEq, DecidableEq

def empty : State := { rows := [] }

inductive Operation where
  | createRows (count : Nat)
  | updateOne (id : Nat)
  | removeEvery (divisor : Nat)
  | swap (first second : Nat)
  | setFilter (filter : Filter)
  | setSort (order : SortOrder)
  | select (id : Nat)
deriving Repr, BEq, DecidableEq

structure Error where
  code : String
  message : String
  path : List String := []
deriving Repr, BEq, DecidableEq

private def findRow? (id : Nat) : List Row → Option Row
  | [] => none
  | row :: rest => if row.id == id then some row else findRow? id rest

private def replaceRows (first second : Row) : List Row → List Row
  | [] => []
  | row :: rest =>
      let next := if row.id == first.id then second
        else if row.id == second.id then first
        else row
      next :: replaceRows first second rest

private def updateRow (id : Nat) : List Row → List Row
  | [] => []
  | row :: rest =>
      (if row.id == id then { row with value := row.value + 1 } else row) :: updateRow id rest

private def removeRows (divisor : Nat) (rows : List Row) : List Row :=
  rows.filter fun row => row.id % divisor != 0

def createRows (count : Nat) : List Row :=
  (List.range count).map Row.create

private def containsId (rows : List Row) (id : Nat) : Bool :=
  rows.any fun row => row.id == id

/-- Independent full-collection state transition. Delta candidates are checked
against the projection produced from this result rather than defining it. -/
def update (state : State) : Operation → Except Error State
  | .createRows count =>
      if count == 0 then .error {
        code := "LRX-GRID-001"
        message := "data-grid row count must be positive"
        path := ["rows"]
      } else if count > 100000 then .error {
        code := "LRX-GRID-002"
        message := "data-grid row count exceeds the checked 100000-row bound"
        path := ["rows"]
      } else .ok {
        rows := createRows count
        filter := .all
        sortOrder := .source
        selected := none
      }
  | .updateOne id =>
      if containsId state.rows id then .ok { state with rows := updateRow id state.rows }
      else .error {
        code := "LRX-GRID-003"
        message := "updated row key does not exist"
        path := [s!"row:{id}"]
      }
  | .removeEvery divisor =>
      if divisor == 0 then .error {
        code := "LRX-GRID-004"
        message := "row-removal divisor must be positive"
        path := ["removeEvery"]
      } else
        let rows := removeRows divisor state.rows
        let selected := state.selected.bind fun id => if containsId rows id then some id else none
        .ok { state with rows, selected }
  | .swap first second =>
      match findRow? first state.rows, findRow? second state.rows with
      | some firstRow, some secondRow =>
          .ok { state with rows := replaceRows firstRow secondRow state.rows }
      | _, _ => .error {
          code := "LRX-GRID-005"
          message := "both swapped row keys must exist"
          path := [s!"row:{first}", s!"row:{second}"]
        }
  | .setFilter filter => .ok { state with filter }
  | .setSort sortOrder => .ok { state with sortOrder }
  | .select id =>
      if containsId state.rows id then .ok { state with selected := some id }
      else .error {
        code := "LRX-GRID-006"
        message := "selected row key does not exist"
        path := [s!"row:{id}"]
      }

private def withSelection (selected : Option Nat) (row : Row) : Row :=
  { row with selected := selected == some row.id }

/-- Canonical logical collection observed by every experiment variant. -/
def visibleRows (state : State) : List Row :=
  let filtered := match state.filter with
    | .all => state.rows
    | .odd => state.rows.filter fun row => row.id % 2 == 1
  let ordered := match state.sortOrder with
    | .source => filtered
    | .descending => filtered.mergeSort fun left right => left.id >= right.id
  ordered.map (withSelection state.selected)

private def updateCandidates : List Row → List Row → Nat → Option (List (ListDelta Row))
  | [], [], _ => some []
  | old :: olds, next :: nexts, index =>
      if old.id != next.id then none
      else do
        let tail ← updateCandidates olds nexts (index + 1)
        pure <| if old == next then tail else .update index next :: tail
  | _, _, _ => none

private def indexOf? (id : Nat) : List Row → Nat → Option Nat
  | [], _ => none
  | row :: rest, index =>
      if row.id == id then some index else indexOf? id rest (index + 1)

private def swapCandidates (rows : List Row) (first second : Nat) : List (ListDelta Row) :=
  match indexOf? first rows 0, indexOf? second rows 0 with
  | some firstIndex, some secondIndex =>
      if firstIndex == secondIndex then []
      else
        let low := min firstIndex secondIndex
        let high := max firstIndex secondIndex
        [.move high low, .move (low + 1) high]
  | _, _ => []

private def removalCandidates (divisor : Nat) : List Row → Nat → List (ListDelta Row)
  | [], _ => []
  | row :: rest, currentIndex =>
      if row.id % divisor == 0 then
        .remove currentIndex :: removalCandidates divisor rest currentIndex
      else
        removalCandidates divisor rest (currentIndex + 1)

private def candidate (operation : Operation) (current target : List Row) : List (ListDelta Row) :=
  match operation with
  | .updateOne _ | .select _ =>
      (updateCandidates current target 0).getD [.reset target.toArray]
  | .removeEvery divisor => removalCandidates divisor current 0
  | .swap first second => swapCandidates current first second
  | .createRows _ | .setFilter _ | .setSort _ => [.reset target.toArray]

def plannedDeltas (state : State) (operation : Operation) (next : State) :
    PlannedDeltas (visibleRows state) (visibleRows next) :=
  let current := visibleRows state
  let target := visibleRows next
  PlannedDeltas.create current target (candidate operation current target)

theorem plannedDeltas_correct (state : State) (operation : Operation) (next : State) :
    ListDelta.applyAll (plannedDeltas state operation next).deltas (visibleRows state) =
      .ok (visibleRows next) :=
  PlannedDeltas.apply_eq_target (plannedDeltas state operation next)

inductive Strategy where
  | full
  | delta
  | hybrid
deriving Repr, BEq, DecidableEq

inductive PlanMode where
  | keyedFull
  | deltaBatch
deriving Repr, BEq, DecidableEq

structure CostModel where
  maxDeltaEdits : Nat
  deltaFixedCost : Nat
  deltaEditCost : Nat
  fullRowCost : Nat
deriving Repr, BEq, DecidableEq

/-- Initial hybrid parameters. M10 benchmarks this explicit policy and the ADR
records that it is an opt-in experiment rather than a universal optimizer law. -/
def defaultCostModel : CostModel := {
  maxDeltaEdits := 256
  deltaFixedCost := 8
  deltaEditCost := 3
  fullRowCost := 1
}

structure Work where
  collectionAllocations : Nat
  derivedEvaluations : Nat
  regionVisits : Nat
  deltaEdits : Nat
deriving Repr, BEq, DecidableEq

namespace Work

def add (left right : Work) : Work := {
  collectionAllocations := left.collectionAllocations + right.collectionAllocations
  derivedEvaluations := left.derivedEvaluations + right.derivedEvaluations
  regionVisits := left.regionVisits + right.regionVisits
  deltaEdits := left.deltaEdits + right.deltaEdits
}

def zero : Work := {
  collectionAllocations := 0
  derivedEvaluations := 0
  regionVisits := 0
  deltaEdits := 0
}

end Work

structure Step where
  state : State
  mode : PlanMode
  deltas : List (ListDelta Row)
  usedReset : Bool
  work : Work
deriving Repr

private def deltaAllocationUnits : List (ListDelta Row) → Nat
  | [] => 0
  | .insert _ _ :: rest | .update _ _ :: rest => 1 + deltaAllocationUnits rest
  | .remove _ :: rest | .move _ _ :: rest => deltaAllocationUnits rest
  | .reset values :: rest => values.size + deltaAllocationUnits rest

private def deltaRegionVisits (currentSize : Nat) : List (ListDelta Row) → Nat
  | [] => 0
  | .reset values :: rest => currentSize + values.size + deltaRegionVisits values.size rest
  | _ :: rest => 1 + deltaRegionVisits currentSize rest

private def chooseHybrid (model : CostModel) (currentSize targetSize : Nat)
    (plan : PlannedDeltas current target) : Bool :=
  let editCount := plan.deltas.length
  let deltaCost := model.deltaFixedCost + editCount * model.deltaEditCost
  let fullCost := targetSize * model.fullRowCost
  ¬plan.usedReset && editCount ≤ model.maxDeltaEdits && deltaCost < fullCost && currentSize > 0

def step (strategy : Strategy) (model : CostModel) (state : State)
    (operation : Operation) : Except Error Step := do
  let next ← update state operation
  let current := visibleRows state
  let target := visibleRows next
  let plan := plannedDeltas state operation next
  let mode := match strategy with
    | .full => .keyedFull
    | .delta => .deltaBatch
    | .hybrid => if chooseHybrid model current.length target.length plan
        then .deltaBatch else .keyedFull
  let work := match mode with
    | .keyedFull => {
        collectionAllocations := target.length
        derivedEvaluations := state.rows.length
        regionVisits := target.length
        deltaEdits := 0
      }
    | .deltaBatch => {
        collectionAllocations := deltaAllocationUnits plan.deltas
        derivedEvaluations := plan.deltas.length
        regionVisits := deltaRegionVisits current.length plan.deltas
        deltaEdits := plan.deltas.length
      }
  pure {
    state := next
    mode
    deltas := if mode == .deltaBatch then plan.deltas else []
    usedReset := mode == .deltaBatch && plan.usedReset
    work
  }

def definingTrace : List Operation := [
  .createRows 10000,
  .updateOne 5000,
  .removeEvery 10,
  .swap 1 9998,
  .setFilter .odd,
  .setSort .descending,
  .select 7777
]

structure TraceResult where
  finalState : State
  work : Work
  modes : List PlanMode
  resetCount : Nat
deriving Repr

def runTrace (strategy : Strategy) (model : CostModel := defaultCostModel) :
    Except Error TraceResult :=
  definingTrace.foldlM (init := {
    finalState := empty
    work := Work.zero
    modes := []
    resetCount := 0
  }) fun result operation => do
    let next ← step strategy model result.finalState operation
    pure {
      finalState := next.state
      work := result.work.add next.work
      modes := result.modes ++ [next.mode]
      resetCount := result.resetCount + if next.usedReset then 1 else 0
    }

end LeanRx.Grid
