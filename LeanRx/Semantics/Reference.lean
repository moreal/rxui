import LeanRx.Semantics.Store

namespace LeanRx.Abstract.Reference

def runDerived : List DerivedStep → Store → Store
  | [], store => store
  | step :: rest, store =>
      let next := store.set step.id (step.evaluator.run store)
      runDerived rest next

def observe (sinks : List SinkStep) (store : Store) : List Int :=
  sinks.map fun sink => sink.evaluator.run store

/-- Full recomputation oracle after applying the final batched source store. -/
def run (program : Program) (old : State) (transaction : SourceTransaction) : RunResult :=
  let sourceStore := transaction.apply old.store
  let finalStore := runDerived program.derived sourceStore
  { store := finalStore
    observations := observe program.sinks finalStore
    derivedEvaluations := program.derived.length
    sinkEvaluations := program.sinks.length }

end LeanRx.Abstract.Reference
