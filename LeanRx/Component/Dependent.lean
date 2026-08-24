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

/-- Closed union of the typed event payload types the generic component
backend lowers (ADR-0038). `String` events accept `value`/`key` payload
bindings; `Bool` events accept `checked` bindings. -/
inductive AnyTypedEvent (Γ : Schema) where
  | string (spec : TypedEventSpec Γ String)
  | bool (spec : TypedEventSpec Γ Bool)

namespace AnyTypedEvent

def name : AnyTypedEvent Γ → String
  | .string spec | .bool spec => spec.name

def parameterName : AnyTypedEvent Γ → String
  | .string spec | .bool spec => spec.parameterName

def span : AnyTypedEvent Γ → SourceSpan
  | .string spec | .bool spec => spec.span

def targetIndex : AnyTypedEvent Γ → Nat
  | .string spec => spec.target.index
  | .bool spec => spec.target.index

def targetName : AnyTypedEvent Γ → String
  | .string spec => spec.target.name
  | .bool spec => spec.target.name

def payloadType : AnyTypedEvent Γ → RuntimeTypeId
  | .string _ => .string
  | .bool _ => .bool

end AnyTypedEvent

end LeanRx
