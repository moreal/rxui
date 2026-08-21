import LeanRx.Region.Keyed

namespace LeanRx.JsFrameworkBenchmark

structure Row where
  id : Nat
  label : String
deriving Repr, BEq

structure State where
  private mk ::
  rows : List Row
  nextId : Nat
  selected : Option Nat
deriving Repr, BEq

def initial : State := ⟨[], 1, none⟩

private def generatedRows (state : State) (count : Nat) : List Row :=
  List.range count |>.map fun offset =>
    let id := state.nextId + offset
    { id, label := s!"Row {id}" }

def replaceRows (state : State) (count : Nat) : State :=
  { rows := generatedRows state count
    nextId := state.nextId + count
    selected := none }

def appendRows (state : State) (count : Nat) : State :=
  { state with
    rows := state.rows ++ generatedRows state count
    nextId := state.nextId + count }

def updateEveryTenth (state : State) : State :=
  { state with rows := state.rows.zipIdx.map fun (row, index) =>
      if index % 10 == 0 then { row with label := row.label ++ " !!!" } else row }

def clear (state : State) : State := { state with rows := [], selected := none }

def swapAt (state : State) (first second : Nat) : State :=
  match state.rows[first]?, state.rows[second]? with
  | some firstRow, some secondRow =>
      { state with rows := state.rows.zipIdx.map fun (row, index) =>
          if index == first then secondRow else if index == second then firstRow else row }
  | _, _ => state

def select (state : State) (id : Nat) : State :=
  if state.rows.any (fun row => row.id == id) then { state with selected := some id }
  else state

def delete (state : State) (id : Nat) : State :=
  { state with
    rows := state.rows.filter (fun row => row.id != id)
    selected := if state.selected == some id then none else state.selected }

inductive Operation where
  | run
  | runLots
  | add
  | update
  | clear
  | swapRows
  | select (id : Nat)
  | delete (id : Nat)
deriving Repr, BEq

structure Spec where
  private mk ::
  name : String
  rowCount : Nat
  largeRowCount : Nat
  updateStride : Nat
  swapFirst : Nat
  swapSecond : Nat
deriving Repr, BEq

namespace Spec

def create (name : String) : Spec := ⟨name, 1000, 10000, 10, 1, 998⟩

structure Checked where
  private mk ::
  spec : Spec
  initial : State
deriving Repr, BEq

def check (spec : Spec) : Except Region.Error Checked := do
  if spec.name.isEmpty then throw {
    code := "LRX-REGION-301"
    message := "JS framework benchmark name must not be empty"
    path := #["component"]
  }
  if spec.rowCount != 1000 || spec.largeRowCount != 10000 || spec.updateStride != 10 ||
      spec.swapFirst != 1 || spec.swapSecond != 998 then throw {
    code := "LRX-TYPE-303"
    message := "JS framework benchmark constants must match the upstream contract"
    path := #["benchmark"]
  }
  pure ⟨spec, JsFrameworkBenchmark.initial⟩

end Spec

def update (spec : Spec) (state : State) : Operation → State
  | .run => replaceRows state spec.rowCount
  | .runLots => replaceRows state spec.largeRowCount
  | .add => appendRows state spec.rowCount
  | .update => updateEveryTenth state
  | .clear => JsFrameworkBenchmark.clear state
  | .swapRows => swapAt state spec.swapFirst spec.swapSecond
  | .select id => JsFrameworkBenchmark.select state id
  | .delete id => JsFrameworkBenchmark.delete state id

end LeanRx.JsFrameworkBenchmark
