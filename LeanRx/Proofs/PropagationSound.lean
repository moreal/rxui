import LeanRx.Semantics.Optimized

namespace LeanRx.Abstract

/-- Exact finite frontier of IDs whose values differ from the previous store. -/
def TracksChanges (old current : Store) (changed : List Nat) : Prop :=
  ∀ id, id ∈ changed ↔ old id ≠ current id

namespace SourceTransaction

theorem apply_eq_of_sourceCount_le (program : Program) (transaction : SourceTransaction)
    (old : Store) (valid : transaction.Valid program) {id : Nat}
    (outside : program.sourceCount ≤ id) : transaction.apply old id = old id := by
  induction transaction generalizing old with
  | nil => rfl
  | cons write rest ih =>
      have writeValid : write.id < program.sourceCount := valid write (by simp)
      have restValid : SourceTransaction.Valid program rest := by
        intro current member
        exact valid current (by simp [member])
      have different : id ≠ write.id := Nat.ne_of_gt (Nat.lt_of_lt_of_le writeValid outside)
      simp only [apply]
      rw [ih (old.set write.id write.value) restValid]
      exact Store.set_other old write.id id write.value different

theorem changedIds_tracks (program : Program) (transaction : SourceTransaction)
    (old : Store) (valid : transaction.Valid program) :
    TracksChanges old (transaction.apply old) (transaction.changedIds program old) := by
  intro id
  simp only [changedIds, List.mem_filter, List.mem_range]
  constructor
  · intro member
    exact of_decide_eq_true member.2
  · intro different
    by_cases source : id < program.sourceCount
    · exact ⟨source, decide_eq_true different⟩
    · have unchanged := transaction.apply_eq_of_sourceCount_le program old valid
        (Nat.le_of_not_gt source)
      exact False.elim (different unchanged.symm)

end SourceTransaction

namespace Reference

theorem runDerived_preserves_below (steps : List DerivedStep) (store : Store)
    (threshold id : Nat) (above : ∀ step ∈ steps, threshold ≤ step.id)
    (below : id < threshold) : runDerived steps store id = store id := by
  induction steps generalizing store with
  | nil => rfl
  | cons step rest ih =>
      have stepAbove : threshold ≤ step.id := above step (by simp)
      have restAbove : ∀ later ∈ rest, threshold ≤ later.id := by
        intro later member
        exact above later (by simp [member])
      simp only [runDerived]
      rw [ih (store.set step.id (step.evaluator.run store)) restAbove]
      exact Store.set_other store step.id id (step.evaluator.run store) <|
        Nat.ne_of_lt (Nat.lt_of_lt_of_le below stepAbove)

theorem runDerived_cache_valid (steps : List DerivedStep) (store : Store)
    (depsBefore : ∀ step ∈ steps, ∀ dep ∈ step.evaluator.deps, dep < step.id)
    (order : steps.Pairwise fun earlier later => earlier.id < later.id) :
    DerivedCacheValid (runDerived steps store) steps := by
  induction steps generalizing store with
  | nil => constructor
  | cons step rest ih =>
      have stepBefore : ∀ later ∈ rest, step.id < later.id :=
        (List.pairwise_cons.mp order).1
      have restOrder := (List.pairwise_cons.mp order).2
      have stepDeps : ∀ dep ∈ step.evaluator.deps, dep < step.id :=
        depsBefore step (by simp)
      have restDeps : ∀ later ∈ rest, ∀ dep ∈ later.evaluator.deps, dep < later.id := by
        intro later member
        exact depsBefore later (by simp [member])
      let next := store.set step.id (step.evaluator.run store)
      have headPreserved : runDerived rest next step.id = next step.id :=
        runDerived_preserves_below rest next (step.id + 1) step.id
          (fun later member => Nat.succ_le_iff.mpr (stepBefore later member))
          (Nat.lt_succ_self step.id)
      have evalStoreNext : step.evaluator.run store = step.evaluator.run next :=
        step.evaluator.congr store next fun dep member =>
          (Store.set_other store step.id dep (step.evaluator.run store) <|
            Nat.ne_of_lt (stepDeps dep member)).symm
      have evalNextFinal : step.evaluator.run next =
          step.evaluator.run (runDerived rest next) :=
        step.evaluator.congr next (runDerived rest next) fun dep member =>
          (runDerived_preserves_below rest next step.id dep
            (fun later laterMember => Nat.le_of_lt (stepBefore later laterMember))
            (stepDeps dep member)).symm
      have headValid : runDerived rest next step.id =
          step.evaluator.run (runDerived rest next) := by
        calc
          runDerived rest next step.id = next step.id := headPreserved
          _ = step.evaluator.run store := Store.set_same store step.id _
          _ = step.evaluator.run next := evalStoreNext
          _ = step.evaluator.run (runDerived rest next) := evalNextFinal
      exact .cons headValid (ih next restDeps restOrder)

theorem observe_cache_valid (sinks : List SinkStep) (store : Store) :
    SinkCacheValid store sinks (observe sinks store) := by
  induction sinks with
  | nil => constructor
  | cons sink rest ih =>
      simp only [observe, List.map]
      exact .cons rfl ih

theorem initialize_valid (program : Program) (wellFormed : program.WellFormed)
    (sourceStore : Store) : (initState program sourceStore).Valid program := by
  constructor
  · exact runDerived_cache_valid program.derived sourceStore
      wellFormed.depsBeforeDerived wellFormed.derivedOrder
  · exact observe_cache_valid program.sinks _

def initializeValid (program : Program) (wellFormed : program.WellFormed)
    (sourceStore : Store) : ValidState program :=
  { state := initState program sourceStore
    valid := initialize_valid program wellFormed sourceStore }

end Reference

namespace Optimized

theorem not_pending_agree {deps changed : List Nat} {old current : Store}
    (tracks : TracksChanges old current changed)
    (notPending : isPending deps changed = false) :
    ∀ id ∈ deps, old id = current id := by
  intro id member
  by_cases equal : old id = current id
  · exact equal
  · have changedMember : id ∈ changed := (tracks id).2 equal
    have contained : changed.contains id = true := by simpa using changedMember
    have pending : isPending deps changed = true := by
      exact List.any_eq_true.mpr ⟨id, member, contained⟩
    exact False.elim <| Bool.false_ne_true (notPending.symm.trans pending)

theorem setChanged_tracks (old current : Store) (changed : List Nat)
    (tracks : TracksChanges old current changed) (id : Nat) (value : Int) :
    TracksChanges old (current.set id value)
      (setChanged changed id (decide (old id ≠ value))) := by
  intro currentId
  by_cases same : currentId = id
  · subst currentId
    by_cases valueSame : old id = value <;> simp [setChanged, Store.set, valueSame]
  · by_cases valueSame : old id = value <;>
      simp [setChanged, Store.set, same, valueSame, tracks currentId]

/-- Equality-stop soundness for one pending decision. -/
theorem step_store_eq (old current : Store) (changed : List Nat) (derived : DerivedStep)
    (tracks : TracksChanges old current changed)
    (cacheValid : old derived.id = derived.evaluator.run old) :
    (step old current changed derived).store =
      current.set derived.id (derived.evaluator.run current) := by
  by_cases pending : isPending derived.evaluator.deps changed = true
  · simp [step, pending]
  · have notPending : isPending derived.evaluator.deps changed = false :=
      Bool.eq_false_iff.mpr pending
    have evalEqual : derived.evaluator.run old = derived.evaluator.run current :=
      derived.evaluator.congr old current <| not_pending_agree tracks notPending
    simp only [step, notPending]
    exact congrArg (current.set derived.id) (cacheValid.trans evalEqual)

theorem step_tracks (old current : Store) (changed : List Nat) (derived : DerivedStep)
    (tracks : TracksChanges old current changed) :
    TracksChanges old (step old current changed derived).store
      (step old current changed derived).changed := by
  by_cases pending : isPending derived.evaluator.deps changed = true
  · simpa [step, pending] using setChanged_tracks old current changed tracks derived.id
      (derived.evaluator.run current)
  · have notPending : isPending derived.evaluator.deps changed = false :=
      Bool.eq_false_iff.mpr pending
    simpa [step, notPending] using setChanged_tracks old current changed tracks derived.id
      (old derived.id)

/-- Every optimized prefix equals full recomputation of that prefix and retains
an exact changed frontier. -/
theorem runDerived_sound (old current : Store) (changed : List Nat)
    (derived : List DerivedStep) (tracks : TracksChanges old current changed)
    (cacheValid : DerivedCacheValid old derived) :
    let result := runDerived old derived current changed
    result.store = Reference.runDerived derived current ∧
      TracksChanges old result.store result.changed := by
  induction cacheValid generalizing current changed with
  | nil => exact ⟨rfl, tracks⟩
  | @cons rest derived valueValid _ restIH =>
      let next := step old current changed derived
      have nextStore : next.store = current.set derived.id (derived.evaluator.run current) :=
        step_store_eq old current changed derived tracks valueValid
      have nextTracks : TracksChanges old next.store next.changed :=
        step_tracks old current changed derived tracks
      have tail := restIH next.store next.changed nextTracks
      constructor
      · simpa only [runDerived, Reference.runDerived, next, nextStore] using tail.1
      · simpa only [runDerived, next] using tail.2

/-- Valid old sink caches match reference observations when pending is derived
from the exact final changed frontier. -/
theorem observe_eq (old current : Store) (changed : List Nat)
    (sinks : List SinkStep) (cache : List Int)
    (tracks : TracksChanges old current changed)
    (cacheValid : SinkCacheValid old sinks cache) :
    (observe changed current sinks cache).values = Reference.observe sinks current := by
  induction cacheValid with
  | nil => rfl
  | @cons cached rest cachedRest sink cachedValid _ restIH =>
      by_cases pending : isPending sink.evaluator.deps changed = true
      · simp [observe, Reference.observe, pending, restIH]
      · have notPending : isPending sink.evaluator.deps changed = false :=
          Bool.eq_false_iff.mpr pending
        have evalEqual : sink.evaluator.run old = sink.evaluator.run current :=
          sink.evaluator.congr old current <| not_pending_agree tracks notPending
        simp [observe, Reference.observe, notPending, cachedValid, evalEqual, restIH]

end Optimized

/-- The final optimized abstract store equals the full-recomputation store. -/
theorem optimized_store_eq_reference
    (program : Program)
    (old : State)
    (derivedCacheValid : DerivedCacheValid old.store program.derived)
    (transaction : SourceTransaction)
    (transactionValid : transaction.Valid program) :
    (Optimized.run program old transaction).store =
      (Reference.run program old transaction).store := by
  let sourceStore := transaction.apply old.store
  let changed := transaction.changedIds program old.store
  have tracks : TracksChanges old.store sourceStore changed :=
    transaction.changedIds_tracks program old.store transactionValid
  exact (Optimized.runDerived_sound old.store sourceStore changed program.derived
    tracks derivedCacheValid).1

/-- Optimized actual-change propagation has the same abstract observations as
full recomputation for a well-formed finite static-DAG program. -/
theorem optimized_equivalent_to_reference
    (program : Program)
    (_wellFormed : program.WellFormed)
    (old : State)
    (derivedCacheValid : DerivedCacheValid old.store program.derived)
    (sinkCacheValid : SinkCacheValid old.store program.sinks old.sinkCache)
    (transaction : SourceTransaction)
    (transactionValid : transaction.Valid program) :
    (Optimized.run program old transaction).observations =
      (Reference.run program old transaction).observations := by
  let sourceStore := transaction.apply old.store
  let changed := transaction.changedIds program old.store
  have sourceTracks : TracksChanges old.store sourceStore changed :=
    transaction.changedIds_tracks program old.store transactionValid
  have derivedSound := Optimized.runDerived_sound old.store sourceStore changed
    program.derived sourceTracks derivedCacheValid
  exact Optimized.observe_eq old.store _ _ program.sinks old.sinkCache
    derivedSound.2 sinkCacheValid |>.trans <| congrArg (Reference.observe program.sinks)
      derivedSound.1

/-- A valid optimized state remains valid after a valid batched transaction, so
the central theorem composes across event sequences without a reference oracle. -/
theorem optimized_nextState_valid
    (program : Program)
    (wellFormed : program.WellFormed)
    (old : ValidState program)
    (transaction : SourceTransaction)
    (transactionValid : transaction.Valid program) :
    (Optimized.run program old.state transaction).nextState.Valid program := by
  have storeEqual := optimized_store_eq_reference program old.state old.valid.1
    transaction transactionValid
  have observationsEqual := optimized_equivalent_to_reference program wellFormed old.state
    old.valid.1 old.valid.2 transaction transactionValid
  constructor
  · change DerivedCacheValid (Optimized.run program old.state transaction).store program.derived
    rw [storeEqual]
    simpa only [Reference.run] using Reference.runDerived_cache_valid program.derived
      (transaction.apply old.state.store) wellFormed.depsBeforeDerived wellFormed.derivedOrder
  · change SinkCacheValid (Optimized.run program old.state transaction).store program.sinks
      (Optimized.run program old.state transaction).observations
    rw [storeEqual, observationsEqual]
    simpa only [Reference.run] using Reference.observe_cache_valid program.sinks
      (Reference.runDerived program.derived (transaction.apply old.state.store))

def optimizedNextValid
    (program : Program)
    (wellFormed : program.WellFormed)
    (old : ValidState program)
    (transaction : SourceTransaction)
    (transactionValid : transaction.Valid program) : ValidState program :=
  { state := (Optimized.run program old.state transaction).nextState
    valid := optimized_nextState_valid program wellFormed old transaction transactionValid }

end LeanRx.Abstract
