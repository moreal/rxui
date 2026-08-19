import LeanRx.Semantics.Reference

namespace LeanRx.Abstract.Optimized

/-- A node is pending exactly when one of its direct dependencies changed. -/
def isPending (deps changed : List Nat) : Bool :=
  deps.any changed.contains

/-- Replace one ID's exact changed/not-changed membership without duplicates. -/
def setChanged (changed : List Nat) (id : Nat) (differs : Bool) : List Nat :=
  let rest := changed.filter (· != id)
  if differs then id :: rest else rest

structure StepResult where
  store : Store
  changed : List Nat
  evaluated : Bool
  valueChanged : Bool

def step (old current : Store) (changed : List Nat) (derived : DerivedStep) : StepResult :=
  if isPending derived.evaluator.deps changed then
    let value := derived.evaluator.run current
    let differs := decide (old derived.id ≠ value)
    { store := current.set derived.id value
      changed := setChanged changed derived.id differs
      evaluated := true
      valueChanged := differs }
  else
    { store := current.set derived.id (old derived.id)
      changed := setChanged changed derived.id false
      evaluated := false
      valueChanged := false }

structure DerivedResult where
  store : Store
  changed : List Nat
  trace : List TraceEvent

def runDerived (old : Store) : List DerivedStep → Store → List Nat → DerivedResult
  | [], current, changed => { store := current, changed, trace := [] }
  | derived :: rest, current, changed =>
      let next := step old current changed derived
      let final := runDerived old rest next.store next.changed
      let events := if next.evaluated then
        [TraceEvent.derivedPending derived.id, .derivedEvaluated derived.id] ++
          (if next.valueChanged then [.derivedChanged derived.id] else [])
        else []
      { store := final.store, changed := final.changed, trace := events ++ final.trace }

structure ObservationResult where
  values : List Int
  trace : List TraceEvent

def observe (changed : List Nat) (current : Store) : List SinkStep → List Int → ObservationResult
  | [], _ => { values := [], trace := [] }
  | sink :: rest, cached :: cachedRest =>
      let pending := isPending sink.evaluator.deps changed
      let value := if pending then sink.evaluator.run current else cached
      let final := observe changed current rest cachedRest
      let events := if pending then
        [TraceEvent.sinkPending sink.name, .sinkEvaluated sink.name]
        else []
      { values := value :: final.values, trace := events ++ final.trace }
  | sink :: rest, [] =>
      let final := observe changed current rest []
      { values := sink.evaluator.run current :: final.values
        trace := [.sinkPending sink.name, .sinkEvaluated sink.name] ++ final.trace }

private def countDerivedEvaluations (trace : List TraceEvent) : Nat :=
  trace.countP fun event => match event with | .derivedEvaluated _ => true | _ => false

private def countSinkEvaluations (trace : List TraceEvent) : Nat :=
  trace.countP fun event => match event with | .sinkEvaluated _ => true | _ => false

/-- Actual-change evaluator with an explicit changed-source frontier and
traceable direct-dependency closure. -/
def run (program : Program) (old : State) (transaction : SourceTransaction) : RunResult :=
  let sourceStore := transaction.apply old.store
  let changedSources := transaction.changedIds program old.store
  let derived := runDerived old.store program.derived sourceStore changedSources
  let observations := observe derived.changed derived.store program.sinks old.sinkCache
  let trace := changedSources.map TraceEvent.sourceChanged ++ derived.trace ++ observations.trace
  { store := derived.store
    observations := observations.values
    derivedEvaluations := countDerivedEvaluations trace
    sinkEvaluations := countSinkEvaluations trace
    trace }

end LeanRx.Abstract.Optimized
