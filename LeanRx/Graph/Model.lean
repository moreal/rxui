import LeanRx.Core.Expr
import LeanRx.Core.SourceInfo

namespace LeanRx

/-- Stable declaration-order graph identifier. -/
structure NodeId where
  value : Nat
deriving Repr, BEq, DecidableEq, Ord

/-- Erased runtime type identity retained by graph and lowering validation. -/
inductive RuntimeTypeId where
  | bool
  | string
  | int
  | nat
deriving Repr, BEq, DecidableEq, Ord

def RuntimeType.id : {α : Type} → RuntimeType α → RuntimeTypeId
  | _, .bool => .bool
  | _, .string => .string
  | _, .int => .int
  | _, .nat => .nat

def RuntimeRep.typeId (α : Type) [rep : RuntimeRep α] : RuntimeTypeId :=
  rep.runtimeType.id

inductive NodeKind where
  | source
  | derived
  | sink
deriving Repr, BEq, DecidableEq, Ord

/-- A direct dependency plus the input type expected by the consumer. -/
structure TypedNodeRef where
  id : NodeId
  valueType : RuntimeTypeId
deriving Repr, BEq, DecidableEq

/-- Declarative node input before stable IDs and ranks are assigned. -/
structure NodeSpec where
  name : String
  kind : NodeKind
  valueType : RuntimeTypeId
  deps : Array TypedNodeRef
  equality : Option JsEqPlan
  evaluator : String
  span : SourceSpan := .generated

namespace NodeSpec

def source (name : String) (valueType : RuntimeTypeId)
    (span : SourceSpan := .generated) : NodeSpec :=
  { name, kind := .source, valueType, deps := #[], equality := none,
    evaluator := "", span }

def derived (name : String) (valueType : RuntimeTypeId) (deps : Array TypedNodeRef)
    (equality : JsEqPlan) (evaluator : String)
    (span : SourceSpan := .generated) : NodeSpec :=
  { name, kind := .derived, valueType, deps, equality := some equality,
    evaluator, span }

def sink (name : String) (deps : Array TypedNodeRef) (evaluator : String)
    (span : SourceSpan := .generated) : NodeSpec :=
  { name, kind := .sink, valueType := .string, deps, equality := none,
    evaluator, span }

end NodeSpec

/-- Validated graph node with a stable ID and computed topological rank. -/
structure Node where
  id : NodeId
  name : String
  kind : NodeKind
  valueType : RuntimeTypeId
  deps : Array NodeId
  rank : Nat
  equality : Option JsEqPlan
  evaluator : String
  span : SourceSpan

structure Graph where
  nodes : Array Node

/-- Stable structured graph diagnostic. -/
structure GraphError where
  code : String
  message : String
  path : Array String := #[]
  spans : Array SourceSpan := #[]
deriving Repr, BEq

end LeanRx
