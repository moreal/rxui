import examples.Counter

namespace LeanRxTest.Elab.Component

open LeanRx LeanRxExamples.Counter

private def verify (checked : CheckedComponent CounterSchema) : IO Unit := do
  unless checked.spec.name == "CounterSyntax" do
    throw <| IO.userError "component command lost the generated component name"
  unless checked.view.textSinks.map (·.name) ==
      ["countText", "doubledText", "parityText", "hostileText"] do
    throw <| IO.userError "JSX interpolation did not become inspectable text sinks"
  unless checked.view.events.map (·.binding.eventName) ==
      ["increment", "addTwo", "nestedAddTwo"] do
    throw <| IO.userError "JSX click attributes did not become event bindings"

def run : IO Unit := do
  unless CounterSyntax_declarations.map SurfaceDecl.debug == [
      "state:count", "derived:doubled", "derived:parity",
      "event:increment", "event:addTwo", "event:nestedAddTwo"
    ] do
    throw <| IO.userError "component command declaration inventory changed"
  unless CounterSyntax_declarations.all (fun declaration =>
      !declaration.span.file.isEmpty && declaration.span.start.line > 0 &&
        declaration.span.start.column > 0) do
    throw <| IO.userError "component command did not retain source-linked declarations"
  match CounterSyntax_check with
  | .error error => throw <| IO.userError s!"generated component rejected: {error.code}"
  | .ok checked => verify checked

end LeanRxTest.Elab.Component
