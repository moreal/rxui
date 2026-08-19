import LeanRx.Core.Expr
import LeanRx.Core.SourceInfo

namespace LeanRx

/-- A compile-time immutable component input with explicit browser
representation evidence. Backends may embed it or expose it through a checked
mount ABI, but updates cannot target it. -/
structure ImmutableProp (α : Type) where
  runtime : RuntimeRep α
  name : String
  value : α

namespace ImmutableProp

def of [runtime : RuntimeRep α] (name : String) (value : α) : ImmutableProp α :=
  { runtime, name, value }

def valueType (prop : ImmutableProp α) : RuntimeTypeId :=
  prop.runtime.runtimeType.id

end ImmutableProp

/-- First-order update driven by a typed event payload. The payload type and
the assignment target are definitionally identical. -/
inductive ParamUpdate (Γ : Schema) (α : Type) where
  | set (target : Field Γ α)

namespace ParamUpdate

def target : ParamUpdate Γ α → Field Γ α
  | .set target => target

end ParamUpdate

/-- Public event description whose payload retains a sealed runtime type. -/
structure TypedEventSpec (Γ : Schema) (α : Type) where
  runtime : RuntimeRep α
  name : String
  parameterName : String
  update : ParamUpdate Γ α
  span : SourceSpan := .generated

namespace TypedEventSpec

def assign [runtime : RuntimeRep α] (name parameterName : String)
    (target : Field Γ α) (span : SourceSpan := .generated) : TypedEventSpec Γ α :=
  { runtime, name, parameterName, update := .set target, span }

def payloadType (event : TypedEventSpec Γ α) : RuntimeTypeId :=
  event.runtime.runtimeType.id

def target (event : TypedEventSpec Γ α) : Field Γ α := event.update.target

end TypedEventSpec

end LeanRx
