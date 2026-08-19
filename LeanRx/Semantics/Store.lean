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

end Program

structure SourceWrite where
  id : Nat
  value : Int

abbrev SourceTransaction := List SourceWrite

namespace SourceTransaction

def apply (transaction : SourceTransaction) (store : Store) : Store :=
  transaction.foldl (fun current write => current.set write.id write.value) store

def Valid (program : Program) (transaction : SourceTransaction) : Prop :=
  ∀ write ∈ transaction, write.id < program.sourceCount

end SourceTransaction

structure State where
  store : Store
  sinkCache : List Int

inductive DerivedCacheValid (old : Store) : List DerivedStep → Prop where
  | nil : DerivedCacheValid old []
  | cons : old step.id = step.evaluator.run old →
      DerivedCacheValid old rest → DerivedCacheValid old (step :: rest)

inductive SinkCacheValid (old : Store) : List SinkStep → List Int → Prop where
  | nil : SinkCacheValid old [] []
  | cons : cached = sink.evaluator.run old → SinkCacheValid old rest cachedRest →
      SinkCacheValid old (sink :: rest) (cached :: cachedRest)

structure RunResult where
  store : Store
  observations : List Int
  derivedEvaluations : Nat
  sinkEvaluations : Nat

end LeanRx.Abstract
