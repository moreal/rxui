import examples.Counter

namespace LeanRxTest.Elab.Component

open LeanRx LeanRxExamples.Counter

private def verify (checked : CheckedComponent CounterSchema) : IO Unit := do
  unless checked.spec.name == "CounterSyntax" do
    throw <| IO.userError "component command lost the generated component name"
  unless checked.view.textSinks.map (·.name) ==
      ["countText", "doubledText", "parityText"] do
    throw <| IO.userError "JSX interpolation did not become inspectable text sinks"
  unless checked.view.events.map (·.binding.eventName) == ["increment", "addTwo"] do
    throw <| IO.userError "JSX click attributes did not become event bindings"

def run : IO Unit := do
  unless CounterSyntax_declarations == [
      "state:count", "derived:doubled", "derived:parity",
      "event:increment", "event:addTwo"
    ] do
    throw <| IO.userError "component command declaration inventory changed"
  match CounterSyntax_check with
  | .error error => throw <| IO.userError s!"generated component rejected: {error.code}"
  | .ok checked => verify checked

end LeanRxTest.Elab.Component
