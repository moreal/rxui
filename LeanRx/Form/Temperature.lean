import LeanRx.Component.Dependent
import LeanRx.Component.Model
import LeanRx.Form.Validation
import LeanRx.Graph.Topological

namespace LeanRx.Form

open LeanRx

abbrev TemperatureState : Schema :=
  .field "celsius" String <| .field "fahrenheit" String .empty

def celsiusField : Field TemperatureState String := .here
def fahrenheitField : Field TemperatureState String := .there .here

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

structure Checked where
  private mk ::
  spec : TemperatureSpec
  graph : PlannedGraph
  celsiusEvent : TypedEventSpec TemperatureState String
  fahrenheitEvent : TypedEventSpec TemperatureState String

private def graphSpecs (spec : TemperatureSpec) : Array NodeSpec := #[
  .source "celsius" .string spec.span,
  .source "fahrenheit" .string spec.span,
  .sink "celsiusValue" .string #[{ id := ⟨0⟩, valueType := .string }]
    "property(celsius.value)" spec.span,
  .sink "fahrenheitValue" .string #[{ id := ⟨1⟩, valueType := .string }]
    "property(fahrenheit.value)" spec.span
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
            celsiusEvent := spec.celsiusEvent
            fahrenheitEvent := spec.fahrenheitEvent
          }

end TemperatureSpec

end LeanRx.Form
