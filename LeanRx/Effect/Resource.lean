import LeanRx.Effect.Model

namespace LeanRx.Effect

/-- Explicit async resource lifecycle. The handle carried by every non-idle
state makes stale-completion suppression a pure checked operation. -/
inductive Resource (α : Type) where
  | idle
  | loading (handle : Handle)
  | success (handle : Handle) (value : α)
  | failure (handle : Handle) (error : Error)
  | cancelled (handle : Handle)
deriving Repr

namespace Resource

def start (handle : Handle) : Resource α := .loading handle

def cancel (handle : Handle) : Resource α → Resource α
  | .loading active => if active = handle then .cancelled handle else .loading active
  | state => state

def settle (handle : Handle) (result : Except Error α) : Resource α → Resource α
  | .loading active =>
      if active = handle then
        match result with
        | .ok value => .success handle value
        | .error error => .failure handle error
      else .loading active
  | state => state

theorem settle_stale (result : Except Error α) (different : stale ≠ active) :
    settle stale result (.loading active) = .loading active := by
  have reversed : active ≠ stale := Ne.symm different
  simp [settle, reversed]

theorem cancel_stale (different : stale ≠ active) :
    cancel stale (.loading active : Resource α) = .loading active := by
  have reversed : active ≠ stale := Ne.symm different
  simp [cancel, reversed]

end Resource

end LeanRx.Effect
