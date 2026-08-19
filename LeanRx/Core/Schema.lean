namespace LeanRx

universe u

/-- A compile-time list of named, heterogeneously typed state fields. -/
inductive Schema : Type (u + 1) where
  | empty
  | field (name : String) (type : Type u) (tail : Schema)

namespace Schema

/-- Number of fields in declaration order. -/
def size : Schema → Nat
  | .empty => 0
  | .field _ _ tail => tail.size + 1

/-- Field names in declaration order. -/
def names : Schema → List String
  | .empty => []
  | .field name _ tail => name :: tail.names

end Schema

/-- An unforgeable capability for a field of type `α` in schema `Γ`. -/
inductive Field : (Γ : Schema.{u}) → Type u → Type (u + 1) where
  | here : Field (.field name α tail) α
  | there : Field tail α → Field (.field name β tail) α

namespace Field

/-- Stable zero-based declaration index. -/
def index : {Γ : Schema} → {α : Type} → Field Γ α → Nat
  | _, _, .here => 0
  | _, _, .there field => field.index + 1

/-- The name stored at this field's typed position. -/
def name : {Γ : Schema} → {α : Type} → Field Γ α → String
  | .field name _ _, _, .here => name
  | .field _ _ _, _, .there field => field.name

/-- The stable index together with its schema-bounds proof. -/
def toFin : {Γ : Schema} → {α : Type} → (field : Field Γ α) → Fin Γ.size
  | .field _ _ _, _, .here => ⟨0, Nat.zero_lt_succ _⟩
  | .field _ _ _, _, .there field =>
      ⟨field.toFin.val + 1, Nat.succ_lt_succ field.toFin.isLt⟩

end Field

end LeanRx
