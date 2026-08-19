import LeanRx.Semantics.Optimized

namespace LeanRx.Abstract

namespace Optimized

/-- Equality-stop soundness for one derived node. A cached value may be reused
only when every declared dependency agrees with the current store. -/
theorem step_store_eq (old current : Store) (derived : DerivedStep)
    (cacheValid : old derived.id = derived.evaluator.run old) :
    (step old current derived).1 =
      current.set derived.id (derived.evaluator.run current) := by
  by_cases unchanged : depsUnchanged derived.evaluator.deps old current = true
  · have evalEqual : derived.evaluator.run old = derived.evaluator.run current :=
      derived.evaluator.congr old current <| agree_of_depsUnchanged unchanged
    simp only [step, unchanged, if_true]
    exact congrArg (current.set derived.id) (cacheValid.trans evalEqual)
  · have changed : depsUnchanged derived.evaluator.deps old current = false :=
      Bool.eq_false_iff.mpr unchanged
    simp [step, changed]

/-- After every optimized prefix, its store agrees with recomputing that same
prefix. This is the topological-prefix lemma used by the central theorem. -/
theorem runDerived_store_eq (old current : Store) (derived : List DerivedStep)
    (cacheValid : DerivedCacheValid old derived) :
    (runDerived old derived current).1 = Reference.runDerived derived current := by
  induction cacheValid generalizing current with
  | nil => rfl
  | @cons rest step valueValid _ restIH =>
      simp only [runDerived, Reference.runDerived]
      rw [step_store_eq old current step valueValid]
      exact restIH (current.set step.id (step.evaluator.run current))

/-- Valid old sink caches produce exactly the reference observations, whether
the optimized evaluator reuses a cache or recomputes a pending sink. -/
theorem observe_eq (old current : Store) (sinks : List SinkStep) (cache : List Int)
    (cacheValid : SinkCacheValid old sinks cache) :
    (observe old current sinks cache).1 = Reference.observe sinks current := by
  induction cacheValid with
  | nil => rfl
  | @cons cached rest cachedRest sink cachedValid _ restIH =>
      by_cases unchanged : depsUnchanged sink.evaluator.deps old current = true
      · have evalEqual : sink.evaluator.run old = sink.evaluator.run current :=
          sink.evaluator.congr old current <| agree_of_depsUnchanged unchanged
        simp [observe, Reference.observe, unchanged, cachedValid,
          restIH, evalEqual]
      · have changed : depsUnchanged sink.evaluator.deps old current = false :=
          Bool.eq_false_iff.mpr unchanged
        simp [observe, Reference.observe, changed, restIH]

end Optimized

/-- The final optimized abstract store equals the full-recomputation store. -/
theorem optimized_store_eq_reference
    (program : Program)
    (old : State)
    (derivedCacheValid : DerivedCacheValid old.store program.derived)
    (transaction : SourceTransaction) :
    (Optimized.run program old transaction).store =
      (Reference.run program old transaction).store := by
  simp only [Optimized.run, Reference.run]
  exact Optimized.runDerived_store_eq old.store
    (transaction.apply old.store) program.derived derivedCacheValid

/-- Optimized actual-change propagation has the same abstract observations as
full recomputation for a well-formed finite static-DAG program. The evaluator
dependency laws are carried by `Eval`; `Int` equality is decidable and lawful;
the program list is the certified topological order represented abstractly. -/
theorem optimized_equivalent_to_reference
    (program : Program)
    (_wellFormed : program.WellFormed)
    (old : State)
    (derivedCacheValid : DerivedCacheValid old.store program.derived)
    (sinkCacheValid : SinkCacheValid old.store program.sinks old.sinkCache)
    (transaction : SourceTransaction)
    (_transactionValid : transaction.Valid program) :
    (Optimized.run program old transaction).observations =
      (Reference.run program old transaction).observations := by
  simp only [Optimized.run, Reference.run]
  rw [Optimized.runDerived_store_eq old.store
    (transaction.apply old.store) program.derived derivedCacheValid]
  exact Optimized.observe_eq old.store
    (Reference.runDerived program.derived (transaction.apply old.store))
    program.sinks old.sinkCache sinkCacheValid

end LeanRx.Abstract
