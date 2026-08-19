import LeanRx.Core.Schema

namespace LeanRx

universe u

/-- A canonical dependency set for fields in `Γ`.

The constructor is not used directly by expression APIs; public operations
normalize IDs into strictly increasing, duplicate-free order. -/
structure DepSet (Γ : Schema.{u}) where
  ids : List Nat
deriving Repr, BEq, DecidableEq

namespace DepSet

private def insertId (value : Nat) : List Nat → List Nat
  | [] => [value]
  | head :: tail =>
      if value < head then
        value :: head :: tail
      else if value = head then
        head :: tail
      else
        head :: insertId value tail

private theorem mem_insertId (needle value : Nat) (ids : List Nat) :
    needle ∈ insertId value ids ↔ needle = value ∨ needle ∈ ids := by
  induction ids with
  | nil => simp [insertId]
  | cons head tail ih =>
      simp only [insertId]
      split <;> rename_i before
      · simp
      · split <;> rename_i equal
        · subst value
          simp
        · simp only [List.mem_cons, ih]
          constructor
          · intro h
            match h with
            | Or.inl atHead => exact Or.inr (Or.inl atHead)
            | Or.inr (Or.inl atValue) => exact Or.inl atValue
            | Or.inr (Or.inr inTail) => exact Or.inr (Or.inr inTail)
          · intro h
            match h with
            | Or.inl atValue => exact Or.inr (Or.inl atValue)
            | Or.inr (Or.inl atHead) => exact Or.inl atHead
            | Or.inr (Or.inr inTail) => exact Or.inr (Or.inr inTail)

private def normalize (ids : List Nat) : List Nat :=
  ids.foldr insertId []

private theorem mem_normalize (needle : Nat) (ids : List Nat) :
    needle ∈ normalize ids ↔ needle ∈ ids := by
  induction ids with
  | nil => simp [normalize]
  | cons head tail ih =>
      unfold normalize
      simp only [List.foldr, List.mem_cons]
      rw [mem_insertId]
      change needle = head ∨ needle ∈ normalize tail ↔ needle = head ∨ needle ∈ tail
      rw [ih]

/-- The empty dependency set. -/
def empty (Γ : Schema.{u}) : DepSet Γ := ⟨[]⟩

/-- The singleton dependency set for one typed field capability. -/
def singleton {Γ : Schema.{u}} {α : Type u} (field : Field Γ α) : DepSet Γ :=
  ⟨[field.index]⟩

/-- Canonical union, independent of input order and duplicates. -/
def union {Γ : Schema.{u}} (left right : DepSet Γ) : DepSet Γ :=
  ⟨normalize (left.ids ++ right.ids)⟩

/-- Membership by stable numeric ID. -/
def HasId {Γ : Schema.{u}} (deps : DepSet Γ) (id : Nat) : Prop :=
  id ∈ deps.ids

/-- Membership of a typed field capability. -/
def Contains {Γ : Schema.{u}} {α : Type u} (deps : DepSet Γ) (field : Field Γ α) : Prop :=
  deps.HasId field.index

theorem hasId_empty {Γ : Schema.{u}} (id : Nat) :
    ¬(empty Γ).HasId id := by
  simp [HasId, empty]

theorem hasId_singleton {Γ : Schema.{u}} {α : Type u} (needle : Nat) (field : Field Γ α) :
    (singleton field).HasId needle ↔ needle = field.index := by
  simp [HasId, singleton]

theorem hasId_union {Γ : Schema.{u}} (needle : Nat) (left right : DepSet Γ) :
    (union left right).HasId needle ↔ left.HasId needle ∨ right.HasId needle := by
  simp [HasId, union, mem_normalize]

theorem contains_singleton {Γ : Schema.{u}} {α : Type u} (field : Field Γ α) :
    (singleton field).Contains field := by
  simp [Contains, hasId_singleton]

theorem contains_union_left {Γ : Schema.{u}} {α : Type u}
    (field : Field Γ α) (left right : DepSet Γ) (h : left.Contains field) :
    (union left right).Contains field := by
  exact (hasId_union field.index left right).2 (Or.inl h)

theorem contains_union_right {Γ : Schema.{u}} {α : Type u}
    (field : Field Γ α) (left right : DepSet Γ) (h : right.Contains field) :
    (union left right).Contains field := by
  exact (hasId_union field.index left right).2 (Or.inr h)

/-- Stable debug form used by graph and golden fixtures. -/
def debug {Γ : Schema.{u}} (deps : DepSet Γ) : String :=
  "{" ++ String.intercalate "," (deps.ids.map toString) ++ "}"

end DepSet

end LeanRx
