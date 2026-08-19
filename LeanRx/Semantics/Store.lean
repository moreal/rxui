namespace LeanRx.Abstract

/-- Homogeneous proof model for finite-DAG propagation. -/
abbrev Store := Nat → Int

namespace Store

def set (store : Store) (id : Nat) (value : Int) : Store :=
  fun current => if current = id then value else store current

theorem set_same (store : Store) (id : Nat) (value : Int) :
    (store.set id value) id = value := by
  simp [set]

theorem set_other (store : Store) (id other : Nat) (value : Int) (different : other ≠ id) :
    (store.set id value) other = store other := by
  simp [set, different]

end Store

/-- Pure evaluator plus a kernel-checked dependency-completeness law. -/
structure Eval where
  deps : List Nat
  run : Store → Int
  congr : ∀ left right, (∀ id ∈ deps, left id = right id) → run left = run right

namespace Eval

def constant (value : Int) : Eval :=
  { deps := []
    run := fun _ => value
    congr := by intros; rfl }

def map (id : Nat) (f : Int → Int) : Eval :=
  { deps := [id]
    run := fun store => f (store id)
    congr := by
      intro left right agree
      exact congrArg f <| agree id (by simp) }

def map₂ (leftId rightId : Nat) (f : Int → Int → Int) : Eval :=
  { deps := if leftId = rightId then [leftId] else [leftId, rightId]
    run := fun store => f (store leftId) (store rightId)
    congr := by
      intro left right agree
      by_cases same : leftId = rightId
      · subst rightId
        exact congrArg (fun value => f value value) <| agree leftId (by simp)
      · have leftEqual := agree leftId (by simp [same])
        have rightEqual := agree rightId (by simp [same])
        calc
          f (left leftId) (left rightId) = f (right leftId) (left rightId) :=
            congrArg (fun value => f value (left rightId)) leftEqual
          _ = f (right leftId) (right rightId) :=
            congrArg (f (right leftId)) rightEqual }

end Eval

structure DerivedStep where
  id : Nat
  evaluator : Eval

structure SinkStep where
  name : String
  evaluator : Eval

structure Program where
  sourceCount : Nat
  derived : List DerivedStep
  sinks : List SinkStep

namespace Program

/-- A dependency ID denotes either a source or a declared derived node. -/
def Declares (program : Program) (id : Nat) : Prop :=
  id < program.sourceCount ∨ ∃ step ∈ program.derived, step.id = id

/-- Abstract static-DAG conditions assumed by the central propagation theorem. -/
structure WellFormed (program : Program) : Prop where
  derivedAfterSources : ∀ step ∈ program.derived, program.sourceCount ≤ step.id
  depsBeforeDerived : ∀ step ∈ program.derived, ∀ dep ∈ step.evaluator.deps, dep < step.id
  derivedOrder : program.derived.Pairwise fun earlier later => earlier.id < later.id
  derivedDepsDeclared : ∀ step ∈ program.derived, ∀ dep ∈ step.evaluator.deps,
    program.Declares dep
  sinkDepsDeclared : ∀ sink ∈ program.sinks, ∀ dep ∈ sink.evaluator.deps,
    program.Declares dep

def declaresChecked (program : Program) (id : Nat) : Bool :=
  decide (id < program.sourceCount) || program.derived.any (·.id == id)

def derivedAfterChecked (program : Program) : Bool :=
  program.derived.all fun step => decide (program.sourceCount ≤ step.id)

def depsBeforeChecked (program : Program) : Bool :=
  program.derived.all fun step =>
    step.evaluator.deps.all fun dep => decide (dep < step.id)

def orderChecked : List DerivedStep → Bool
  | [] => true
  | step :: rest => rest.all (fun later => decide (step.id < later.id)) && orderChecked rest

def derivedDeclaredChecked (program : Program) : Bool :=
  program.derived.all fun step => step.evaluator.deps.all program.declaresChecked

def sinksDeclaredChecked (program : Program) : Bool :=
  program.sinks.all fun sink => sink.evaluator.deps.all program.declaresChecked

def checkWellFormed (program : Program) : Bool :=
  program.derivedAfterChecked &&
    (program.depsBeforeChecked &&
      (orderChecked program.derived &&
        (program.derivedDeclaredChecked && program.sinksDeclaredChecked)))

end Program

structure SourceWrite where
  id : Nat
  value : Int

abbrev SourceTransaction := List SourceWrite

namespace SourceTransaction

def apply : SourceTransaction → Store → Store
  | [], store => store
  | write :: rest, store => apply rest (store.set write.id write.value)

def Valid (program : Program) (transaction : SourceTransaction) : Prop :=
  ∀ write ∈ transaction, write.id < program.sourceCount

/-- Source IDs whose final batched value differs from the previous store. -/
def changedIds (program : Program) (transaction : SourceTransaction) (old : Store) : List Nat :=
  let current := transaction.apply old
  (List.range program.sourceCount).filter fun id => decide (old id ≠ current id)

end SourceTransaction

structure State where
  store : Store
  sinkCache : List Int

inductive TraceEvent where
  | sourceChanged (id : Nat)
  | derivedPending (id : Nat)
  | derivedEvaluated (id : Nat)
  | derivedChanged (id : Nat)
  | sinkPending (name : String)
  | sinkEvaluated (name : String)
deriving Repr, BEq, DecidableEq

inductive DerivedCacheValid (old : Store) : List DerivedStep → Prop where
  | nil : DerivedCacheValid old []
  | cons : old step.id = step.evaluator.run old →
      DerivedCacheValid old rest → DerivedCacheValid old (step :: rest)

inductive SinkCacheValid (old : Store) : List SinkStep → List Int → Prop where
  | nil : SinkCacheValid old [] []
  | cons : cached = sink.evaluator.run old → SinkCacheValid old rest cachedRest →
      SinkCacheValid old (sink :: rest) (cached :: cachedRest)

namespace State

def Valid (program : Program) (state : State) : Prop :=
  DerivedCacheValid state.store program.derived ∧
    SinkCacheValid state.store program.sinks state.sinkCache

end State

structure ValidState (program : Program) where
  state : State
  valid : state.Valid program

structure RunResult where
  store : Store
  observations : List Int
  derivedEvaluations : Nat
  sinkEvaluations : Nat
  trace : List TraceEvent

def RunResult.nextState (result : RunResult) : State :=
  { store := result.store, sinkCache := result.observations }

end LeanRx.Abstract
