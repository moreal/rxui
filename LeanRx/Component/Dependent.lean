import LeanRx.Core.Expr
import LeanRx.Core.SourceInfo
import LeanRx.View.Model

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

/-- One component-scope payload broadcast event (ADR-0061): the delegated
`checked` boolean of one typed component event flows into an ADR-0050 region
broadcast — `event toggleAll (checked : Bool) := update items (set done
checked)`. The payload identifier is admitted only as a bare `set` right-hand
side, lowering to the `"true"`/`"false"` strings exactly as the ADR-0049 row
`checked` payload does; every other right-hand side stays a sealed
payload-free row expression, and the body is exactly one broadcast — no state
write, no append, no sequencing. The spec carries no schema: like the plain
ADR-0050 broadcast it reads no component state. -/
structure BroadcastEventSpec where
  name : String
  parameterName : String
  region : String
  assignments : List (Nat × RowExpr)
  span : SourceSpan := .generated
deriving Repr, BEq

/-- Closed union of the typed event payload types the generic component
backend lowers (ADR-0038). `String` events accept `value`/`key` payload
bindings; `Bool` events accept `checked` bindings. `boolBroadcast` is the
ADR-0061 payload broadcast — a `Bool` event whose body is one region
broadcast instead of a state assignment; only the checked payload may
broadcast, so no `String` counterpart exists. -/
inductive AnyTypedEvent (Γ : Schema) where
  | string (spec : TypedEventSpec Γ String)
  | bool (spec : TypedEventSpec Γ Bool)
  | boolBroadcast (spec : BroadcastEventSpec)

namespace AnyTypedEvent

def name : AnyTypedEvent Γ → String
  | .string spec | .bool spec => spec.name
  | .boolBroadcast spec => spec.name

def parameterName : AnyTypedEvent Γ → String
  | .string spec | .bool spec => spec.parameterName
  | .boolBroadcast spec => spec.parameterName

def span : AnyTypedEvent Γ → SourceSpan
  | .string spec | .bool spec => spec.span
  | .boolBroadcast spec => spec.span

/-- The written state slot of a payload assignment; an ADR-0061 payload
broadcast writes rows, never component state. -/
def targetIndex? : AnyTypedEvent Γ → Option Nat
  | .string spec => some spec.target.index
  | .bool spec => some spec.target.index
  | .boolBroadcast _ => none

/-- The written state name of a payload assignment; an ADR-0061 payload
broadcast writes rows, never component state. -/
def targetName? : AnyTypedEvent Γ → Option String
  | .string spec => some spec.target.name
  | .bool spec => some spec.target.name
  | .boolBroadcast _ => none

def payloadType : AnyTypedEvent Γ → RuntimeTypeId
  | .string _ => .string
  | .bool _ | .boolBroadcast _ => .bool

/-- The region broadcast body of an ADR-0061 payload broadcast event. -/
def broadcast? : AnyTypedEvent Γ → Option (String × List (Nat × RowExpr))
  | .string _ | .bool _ => none
  | .boolBroadcast spec => some (spec.region, spec.assignments)

end AnyTypedEvent

end LeanRx
