import LeanRx.Component.Dependent
import LeanRx.Component.Model
import LeanRx.Form.Dom
import LeanRx.Form.Validation
import LeanRx.Graph.Topological

namespace LeanRx.Form

open LeanRx

abbrev ValidatedFormState : Schema :=
  .field "name" String <| .field "age" String <| .field "accepted" Bool .empty

def formNameField : Field ValidatedFormState String := .here
def formAgeField : Field ValidatedFormState String := .there .here
def formAcceptedField : Field ValidatedFormState Bool := .there (.there .here)

structure ValidatedFormSpec where
  private mk ::
  name : String
  initial : RawForm
  span : SourceSpan := .generated

namespace ValidatedFormSpec

def create (name : String) (initial : RawForm)
    (span : SourceSpan := .generated) : ValidatedFormSpec :=
  { name, initial, span }

def nameEvent (spec : ValidatedFormSpec) : TypedEventSpec ValidatedFormState String :=
  TypedEventSpec.assign "editName" "value" formNameField spec.span

def ageEvent (spec : ValidatedFormSpec) : TypedEventSpec ValidatedFormState String :=
  TypedEventSpec.assign "editAge" "value" formAgeField spec.span

def acceptedEvent (spec : ValidatedFormSpec) : TypedEventSpec ValidatedFormState Bool :=
  TypedEventSpec.assign "toggleAccepted" "checked" formAcceptedField spec.span

def submitBinding (_ : ValidatedFormSpec) : ControlBinding Unit :=
  { event := .submit, handlerName := "submitValidated" }

def keyBinding (_ : ValidatedFormSpec) : ControlBinding String :=
  { event := .keyDown, handlerName := "recordKey" }

def focusBinding (_ : ValidatedFormSpec) : ControlBinding Unit :=
  { event := .focus, handlerName := "focusField" }

def blurBinding (_ : ValidatedFormSpec) : ControlBinding Unit :=
  { event := .blur, handlerName := "blurField" }

structure Checked where
  private mk ::
  spec : ValidatedFormSpec
  graph : PlannedGraph
  nameEvent : TypedEventSpec ValidatedFormState String
  ageEvent : TypedEventSpec ValidatedFormState String
  acceptedEvent : TypedEventSpec ValidatedFormState Bool
  submitBinding : ControlBinding Unit
  keyBinding : ControlBinding String
  focusBinding : ControlBinding Unit
  blurBinding : ControlBinding Unit

private def graphSpecs (spec : ValidatedFormSpec) : Array NodeSpec := #[
  .source "name" .string spec.span,
  .source "age" .string spec.span,
  .source "accepted" .bool spec.span,
  .sink "nameError" .string #[{ id := ⟨0⟩, valueType := .string }]
    "validate(nonempty,name)" spec.span,
  .sink "ageError" .string #[{ id := ⟨1⟩, valueType := .string }]
    "validate(boundedNat,age)" spec.span,
  .sink "termsError" .string #[{ id := ⟨2⟩, valueType := .bool }]
    "validate(accepted,terms)" spec.span,
  .sink "submitDisabled" .bool #[
    { id := ⟨0⟩, valueType := .string },
    { id := ⟨1⟩, valueType := .string },
    { id := ⟨2⟩, valueType := .bool }
  ] "property(submit.disabled)" spec.span
]

def check (spec : ValidatedFormSpec) : Except ComponentError Checked :=
  if spec.name.isEmpty then .error {
    code := "LRX-ELAB-202"
    message := "validated form component name must not be empty"
    spans := #[spec.span]
  } else
    match Graph.plan (graphSpecs spec) with
    | .error error => .error {
        code := error.code
        message := error.message
        path := error.path
        spans := error.spans
      }
    | .ok graph => .ok {
        spec
        graph
        nameEvent := spec.nameEvent
        ageEvent := spec.ageEvent
        acceptedEvent := spec.acceptedEvent
        submitBinding := spec.submitBinding
        keyBinding := spec.keyBinding
        focusBinding := spec.focusBinding
        blurBinding := spec.blurBinding
      }

end ValidatedFormSpec

end LeanRx.Form
