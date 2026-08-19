import LeanRx.Component.Dependent
import LeanRx.Component.Model
import LeanRx.Form.Dom
import LeanRx.Form.Validation
import LeanRx.Graph.Topological

namespace LeanRx.Form

open LeanRx

abbrev TemperatureState : Schema :=
  .field "celsius" String <| .field "fahrenheit" String <|
    .field "activeCelsius" Bool .empty

def celsiusField : Field TemperatureState String := .here
def fahrenheitField : Field TemperatureState String := .there .here
def activeCelsiusField : Field TemperatureState Bool := .there (.there .here)

structure TemperatureSpec where
  private mk ::
  name : String
  initialCelsius : String
  initialFahrenheit : String
  span : SourceSpan := .generated

namespace TemperatureSpec

def create (name initialCelsius initialFahrenheit : String)
    (span : SourceSpan := .generated) : TemperatureSpec :=
  { name, initialCelsius, initialFahrenheit, span }

def celsiusEvent (spec : TemperatureSpec) :
    TypedEventSpec TemperatureState String :=
  TypedEventSpec.assign "editCelsius" "value" celsiusField spec.span

def fahrenheitEvent (spec : TemperatureSpec) :
    TypedEventSpec TemperatureState String :=
  TypedEventSpec.assign "editFahrenheit" "value" fahrenheitField spec.span

/-- Checked event-local update plan. Parsing reads only the edited raw field;
successful conversion performs a second source write to the explicit opposite
field. Event-local writes are phase-separated from graph propagation and do not
form derived edges. -/
structure UpdatePlan where
  private mk ::
  binding : StateControlBinding TemperatureState String
  scale : TemperatureScale
  activeTarget : Field TemperatureState Bool
  activeCelsius : Bool
  convertedTarget : Field TemperatureState String
  convertedProperty : DomProperty String

namespace UpdatePlan

def celsius (spec : TemperatureSpec) : UpdatePlan :=
  ⟨.textInput spec.celsiusEvent, .celsius, activeCelsiusField, true,
    fahrenheitField, .value⟩

def fahrenheit (spec : TemperatureSpec) : UpdatePlan :=
  ⟨.textInput spec.fahrenheitEvent, .fahrenheit, activeCelsiusField, false,
    celsiusField, .value⟩

def writeTargetIndices (plan : UpdatePlan) : Array Nat :=
  #[plan.binding.target.index, plan.activeTarget.index, plan.convertedTarget.index]

end UpdatePlan

structure Checked where
  private mk ::
  spec : TemperatureSpec
  graph : PlannedGraph
  celsiusUpdate : UpdatePlan
  fahrenheitUpdate : UpdatePlan

private def graphSpecs (spec : TemperatureSpec) : Array NodeSpec := #[
  .source "celsius" .string spec.span,
  .source "fahrenheit" .string spec.span,
  .source "activeCelsius" .bool spec.span,
  .sink "celsiusValue" .string #[{ id := ⟨0⟩, valueType := .string }]
    "property(celsius.value)" spec.span,
  .sink "fahrenheitValue" .string #[{ id := ⟨1⟩, valueType := .string }]
    "property(fahrenheit.value)" spec.span,
  .sink "temperatureError" .string #[
    { id := ⟨0⟩, valueType := .string }, { id := ⟨1⟩, valueType := .string },
    { id := ⟨2⟩, valueType := .bool }]
    "validation(signedInteger)" spec.span,
  .sink "celsiusInvalid" .bool #[
    { id := ⟨0⟩, valueType := .string }, { id := ⟨1⟩, valueType := .string },
    { id := ⟨2⟩, valueType := .bool }]
    "attribute(celsius.aria-invalid)" spec.span,
  .sink "fahrenheitInvalid" .bool #[
    { id := ⟨0⟩, valueType := .string }, { id := ⟨1⟩, valueType := .string },
    { id := ⟨2⟩, valueType := .bool }]
    "attribute(fahrenheit.aria-invalid)" spec.span
]

def check (spec : TemperatureSpec) : Except ComponentError Checked :=
  if spec.name.isEmpty then .error {
    code := "LRX-ELAB-201"
    message := "temperature component name must not be empty"
    spans := #[spec.span]
  } else
    match parseTemperature { scale := .celsius, raw := spec.initialCelsius } with
    | .error error => .error {
        code := error.code
        message := "initial Celsius value is invalid: " ++ error.message
        path := #["celsius"]
        spans := #[spec.span]
      }
    | .ok celsius =>
      if toString celsius.converted != spec.initialFahrenheit then .error {
        code := "LRX-TYPE-206"
        message := "initial Celsius and Fahrenheit values are inconsistent"
        path := #["celsius", "fahrenheit"]
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
            celsiusUpdate := .celsius spec
            fahrenheitUpdate := .fahrenheit spec
          }

end TemperatureSpec

end LeanRx.Form
