import LeanRx.Component.Dependent
import LeanRx.Core.RuntimeRep

namespace LeanRx.Form

/-- Closed DOM property capability. Property names are compiler-owned and the
index fixes the only payload type accepted by lowering. -/
inductive DomProperty : Type → Type where
  | value : DomProperty String
  | checked : DomProperty Bool
  | disabled : DomProperty Bool

namespace DomProperty

def name : {α : Type} → DomProperty α → String
  | _, .value => "value"
  | _, .checked => "checked"
  | _, .disabled => "disabled"

end DomProperty

/-- Closed browser event payloads required by controlled forms. -/
inductive ControlEvent : Type → Type where
  | input : ControlEvent String
  | change : ControlEvent String
  | checkedChange : ControlEvent Bool
  | submit : ControlEvent Unit
  | keyDown : ControlEvent String
  | focus : ControlEvent Unit
  | blur : ControlEvent Unit

namespace ControlEvent

def name : {α : Type} → ControlEvent α → String
  | _, .input => "input"
  | _, .change | _, .checkedChange => "change"
  | _, .submit => "submit"
  | _, .keyDown => "keydown"
  | _, .focus => "focus"
  | _, .blur => "blur"

inductive PayloadKind where
  | text
  | checked
  | none
  | key
deriving Repr, BEq, DecidableEq

def payloadKind : {α : Type} → ControlEvent α → PayloadKind
  | _, .input | _, .change => .text
  | _, .checkedChange => .checked
  | _, .submit | _, .focus | _, .blur => .none
  | _, .keyDown => .key

end ControlEvent

/-- One typed event binding. The backend chooses a fixed host listener from the
event constructor; callers cannot invent event names or payload extraction. -/
structure ControlBinding (α : Type) where
  event : ControlEvent α
  handlerName : String

/-- A source update, browser payload adapter, and reflected DOM property kept in
one typed capability. Private construction prevents a checked payload from being
paired with a different property or host adapter. -/
structure StateControlBinding (Γ : Schema) (α : Type) where
  private mk ::
  event : ControlEvent α
  property : DomProperty α
  update : TypedEventSpec Γ α

namespace StateControlBinding

def textInput (update : TypedEventSpec Γ String) : StateControlBinding Γ String :=
  ⟨.input, .value, update⟩

def textChange (update : TypedEventSpec Γ String) : StateControlBinding Γ String :=
  ⟨.change, .value, update⟩

def checkedChange (update : TypedEventSpec Γ Bool) : StateControlBinding Γ Bool :=
  ⟨.checkedChange, .checked, update⟩

def target (binding : StateControlBinding Γ α) : Field Γ α :=
  binding.update.target

def payloadType (binding : StateControlBinding Γ α) : RuntimeTypeId :=
  binding.update.payloadType

end StateControlBinding

end LeanRx.Form
