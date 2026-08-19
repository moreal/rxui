import LeanRx.Core.Dependency

namespace LeanRx

universe u

/-- A logical heterogeneous store whose value shape is fixed by `Γ`. -/
inductive Store : Schema.{u} → Type (u + 1) where
  | empty : Store .empty
  | cons (value : α) (tail : Store Γ) : Store (.field name α Γ)

namespace Store

/-- Read through a typed field capability; no cast is involved. -/
def get : {Γ : Schema.{u}} → {α : Type u} → Store Γ → Field Γ α → α
  | _, _, .cons value _, .here => value
  | _, _, .cons _ tail, .there field => tail.get field

/-- Purely replace one field while preserving every other typed slot. -/
def set : {Γ : Schema.{u}} → {α : Type u} → Store Γ → Field Γ α → α → Store Γ
  | _, _, .cons _ tail, .here, value => .cons value tail
  | _, _, .cons head tail, .there field, value => .cons head (tail.set field value)

/-- Two stores agree on exactly the typed fields named by `deps`. -/
def AgreeOn {Γ : Schema.{u}} (deps : DepSet Γ) (left right : Store Γ) : Prop :=
  ∀ {α : Type u} (field : Field Γ α), deps.Contains field →
    left.get field = right.get field

theorem get_set_same {Γ : Schema.{u}} {α : Type u}
    (store : Store Γ) (field : Field Γ α) (value : α) :
    (store.set field value).get field = value := by
  induction field with
  | here =>
      cases store with
      | cons => rfl
  | there field ih =>
      cases store with
      | cons _ tail => exact ih tail value

theorem agreeOn_empty {Γ : Schema.{u}} (left right : Store Γ) :
    AgreeOn (DepSet.empty Γ) left right := by
  unfold AgreeOn
  intro _ field absent
  exact False.elim <| DepSet.hasId_empty field.index absent

theorem agreeOn_union_left {Γ : Schema.{u}} (left right : Store Γ)
    (first second : DepSet Γ) (h : AgreeOn (DepSet.union first second) left right) :
    AgreeOn first left right := by
  unfold AgreeOn at h ⊢
  intro _ field member
  exact h field <| DepSet.contains_union_left field first second member

theorem agreeOn_union_right {Γ : Schema.{u}} (left right : Store Γ)
    (first second : DepSet Γ) (h : AgreeOn (DepSet.union first second) left right) :
    AgreeOn second left right := by
  unfold AgreeOn at h ⊢
  intro _ field member
  exact h field <| DepSet.contains_union_right field first second member

end Store

end LeanRx
