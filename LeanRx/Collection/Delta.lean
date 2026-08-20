namespace LeanRx.Collection

/-- A closed structural edit vocabulary. Indices are interpreted against the
collection produced by all preceding edits in the same batch. -/
inductive ListDelta (α : Type u) where
  | insert (index : Nat) (value : α)
  | remove (index : Nat)
  | update (index : Nat) (value : α)
  | move (fromIndex toIndex : Nat)
  | reset (values : Array α)
deriving Repr

/-- Source-linked lowering may wrap this pure diagnostic later. The collection
semantics itself reports stable codes and never guesses at invalid indices. -/
structure Error where
  code : String
  message : String
  index : Nat
  size : Nat
deriving Repr, BEq

private def invalid (code message : String) (index size : Nat) : Except Error α :=
  .error { code, message, index, size }

private def insertAtRaw (values : List α) (index : Nat) (value : α) : List α :=
  match values, index with
  | values, 0 => value :: values
  | head :: tail, index + 1 => head :: insertAtRaw tail index value
  | [], _ => []

private def insertAt (values : List α) (index : Nat) (value : α) : Except Error (List α) :=
  if index ≤ values.length then .ok (insertAtRaw values index value)
  else invalid "LRX-DELTA-001" "insert index is greater than collection length"
    index values.length

private def removeAtRaw (values : List α) (index : Nat) : List α :=
  match values, index with
  | _ :: tail, 0 => tail
  | head :: tail, index + 1 => head :: removeAtRaw tail index
  | [], _ => []

private def removeAt (values : List α) (index : Nat) : Except Error (List α) :=
  if index < values.length then .ok (removeAtRaw values index)
  else invalid "LRX-DELTA-002" "remove index is outside the collection" index values.length

private def updateAtRaw (values : List α) (index : Nat) (value : α) : List α :=
  match values, index with
  | _ :: tail, 0 => value :: tail
  | head :: tail, index + 1 => head :: updateAtRaw tail index value
  | [], _ => []

private def updateAt (values : List α) (index : Nat) (value : α) : Except Error (List α) :=
  if index < values.length then .ok (updateAtRaw values index value)
  else invalid "LRX-DELTA-003" "update index is outside the collection" index values.length

private def takeAtRaw (values : List α) (index : Nat) : Option (α × List α) :=
  match values, index with
  | head :: tail, 0 => some (head, tail)
  | head :: tail, index + 1 => do
      let (value, rest) ← takeAtRaw tail index
      pure (value, head :: rest)
  | [], _ => none

private def takeAt (values : List α) (index : Nat) : Except Error (α × List α) :=
  match takeAtRaw values index with
  | some result => .ok result
  | none => invalid "LRX-DELTA-004" "move source index is outside the collection"
      index values.length

private def moveAt (values : List α) (fromIndex toIndex : Nat) : Except Error (List α) := do
  let (value, rest) ← takeAt values fromIndex
  if toIndex ≤ rest.length then
    return insertAtRaw rest toIndex value
  else
    throw {
      code := "LRX-DELTA-005"
      message := "move target index is outside the collection"
      index := toIndex
      size := rest.length
    }

namespace ListDelta

/-- Apply one checked edit. Invalid indices fail loudly rather than becoming
silent no-ops or guessed resets. -/
def apply (values : List α) : ListDelta α → Except Error (List α)
  | .insert index value => insertAt values index value
  | .remove index => removeAt values index
  | .update index value => updateAt values index value
  | .move fromIndex toIndex => moveAt values fromIndex toIndex
  | .reset target => .ok target.toList

def applyAll : List (ListDelta α) → List α → Except Error (List α)
  | [], values => .ok values
  | delta :: rest, values => do
      applyAll rest (← delta.apply values)

@[simp] theorem apply_reset (values : List α) (target : Array α) :
    (ListDelta.reset target).apply values = .ok target.toList := rfl

@[simp] theorem applyAll_reset (values : List α) (target : Array α) :
    applyAll [ListDelta.reset target] values = .ok target.toList := rfl

end ListDelta

/-- A proof-carrying delta batch. Candidate generation remains executable and
fallible, while every value crossing this boundary is certified to reproduce the
full target collection. -/
structure PlannedDeltas (current target : List α) where
  private mk ::
  deltas : List (ListDelta α)
  correct : ListDelta.applyAll deltas current = .ok target

namespace PlannedDeltas

/-- Retain a candidate exactly when it reproduces the independent full result;
otherwise fall back to one explicit reset. The fallback is observable so
benchmarks cannot mistake it for incremental work. -/
def create [DecidableEq α] (current target : List α)
    (candidate : List (ListDelta α)) : PlannedDeltas current target :=
  match hApply : ListDelta.applyAll candidate current with
  | .ok actual =>
      if h : actual = target then
        ⟨candidate, hApply.trans (congrArg Except.ok h)⟩
      else
        ⟨[.reset target.toArray], by simp⟩
  | .error _ =>
      ⟨[.reset target.toArray], by simp⟩

def usedReset (plan : PlannedDeltas current target) : Bool :=
  plan.deltas.any fun delta => match delta with
    | .reset _ => true
    | _ => false

theorem apply_eq_target (plan : PlannedDeltas current target) :
    ListDelta.applyAll plan.deltas current = .ok target := plan.correct

end PlannedDeltas

end LeanRx.Collection
