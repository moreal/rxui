import LeanRx.Core.RuntimeRep

namespace LeanRx

/-- JavaScript equality strategy emitted for a represented value. -/
inductive JsEqPlan where
  | strict
  | bigint
  | structural
deriving Repr, BEq, DecidableEq

/-- A browser-lowerable equality together with its semantic law. -/
class RuntimeEq (α : Type) [RuntimeRep α] where
  eq : α → α → Bool
  lawful : ∀ a b, eq a b = true ↔ a = b

namespace RuntimeEq

theorem decide_lawful [DecidableEq α] (a b : α) :
    decide (a = b) = true ↔ a = b :=
  ⟨of_decide_eq_true, decide_eq_true⟩

/-- Construct lawful runtime equality from Lean's decidable equality. -/
@[instance_reducible]
def ofDecidable (α : Type) [RuntimeRep α] [DecidableEq α] : RuntimeEq α where
  eq a b := decide (a = b)
  lawful := decide_lawful

/-- Invoke the chosen equality plan. -/
def same (left right : α) [RuntimeRep α] [eq : RuntimeEq α] : Bool :=
  eq.eq left right

/-- Equality lowering is derived from the sealed runtime representation. -/
def jsPlan (α : Type) [rep : RuntimeRep α] : JsEqPlan :=
  match rep.runtimeType with
  | .bool => .strict
  | .string => .strict
  | .int => .bigint
  | .nat => .bigint

end RuntimeEq

instance : RuntimeEq Bool := RuntimeEq.ofDecidable Bool
instance : RuntimeEq String := RuntimeEq.ofDecidable String
instance : RuntimeEq Int := RuntimeEq.ofDecidable Int
instance : RuntimeEq Nat := RuntimeEq.ofDecidable Nat

end LeanRx
