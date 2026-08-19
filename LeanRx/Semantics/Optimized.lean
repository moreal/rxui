import LeanRx.Semantics.Reference

namespace LeanRx.Abstract.Optimized

/-- Static dependency comparison used to decide whether a node is pending. -/
def depsUnchanged (deps : List Nat) (old current : Store) : Bool :=
  deps.all fun id => decide (old id = current id)

theorem agree_of_depsUnchanged {deps : List Nat} {old current : Store}
    (unchanged : depsUnchanged deps old current = true) :
    ∀ id ∈ deps, old id = current id := by
  intro id member
  have checked := (List.all_eq_true.mp unchanged) id member
  exact of_decide_eq_true checked

def step (old current : Store) (derived : DerivedStep) : Store × Bool :=
  if depsUnchanged derived.evaluator.deps old current then
    (current.set derived.id (old derived.id), false)
  else
    (current.set derived.id (derived.evaluator.run current), true)

def runDerived (old : Store) : List DerivedStep → Store → Store × Nat
  | [], current => (current, 0)
  | derived :: rest, current =>
      let (next, evaluated) := step old current derived
      let (final, count) := runDerived old rest next
      (final, count + if evaluated then 1 else 0)

def observe (old current : Store) : List SinkStep → List Int → List Int × Nat
  | [], _ => ([], 0)
  | sink :: rest, cached :: cachedRest =>
      let (value, evaluated) :=
        if depsUnchanged sink.evaluator.deps old current then (cached, false)
        else (sink.evaluator.run current, true)
      let (values, count) := observe old current rest cachedRest
      (value :: values, count + if evaluated then 1 else 0)
  | sink :: rest, [] =>
      let (values, count) := observe old current rest []
      (sink.evaluator.run current :: values, count + 1)

/-- Actual-change evaluator: compare direct dependencies, evaluate once when
pending, and retain old cache values when lawful equality says unchanged. -/
def run (program : Program) (old : State) (transaction : SourceTransaction) : RunResult :=
  let sourceStore := transaction.apply old.store
  let (finalStore, derivedCount) := runDerived old.store program.derived sourceStore
  let (observations, sinkCount) := observe old.store finalStore program.sinks old.sinkCache
  { store := finalStore
    observations
    derivedEvaluations := derivedCount
    sinkEvaluations := sinkCount }

end LeanRx.Abstract.Optimized
