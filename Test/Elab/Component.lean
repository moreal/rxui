import examples.Counter
import examples.EchoLab

namespace LeanRxTest.Elab.Component

open LeanRx LeanRxExamples.Counter

private def verify (checked : CheckedComponent CounterSchema) : IO Unit := do
  unless checked.spec.name == "CounterSyntax" do
    throw <| IO.userError "component command lost the generated component name"
  unless checked.view.textSinks.map (·.name) ==
      ["countText", "doubledText", "parityText", "stableText", "hostileText"] do
    throw <| IO.userError "JSX interpolation did not become inspectable text sinks"
  unless checked.view.events.map (·.binding.eventName) ==
      ["increment", "addTwo", "nestedAddTwo", "roundTrip"] do
    throw <| IO.userError "JSX click attributes did not become event bindings"

private def verifyEcho (checked : CheckedComponent LeanRxExamples.EchoLab.EchoSchema) :
    IO Unit := do
  unless checked.spec.typedEvents.toList.map (·.name) ==
      ["setDraft", "recordKey", "commitNote"] do
    throw <| IO.userError "typed event declarations lost their names"
  unless checked.spec.typedEvents.toList.map (·.parameterName) ==
      ["value", "value", "value"] do
    throw <| IO.userError "typed event declarations lost their payload parameters"
  unless checked.view.events.map
      (fun mounted => (mounted.binding.kind.name, mounted.binding.eventName)) == [
        ("input", "setDraft"), ("keydown", "recordKey"),
        ("change", "commitNote"), ("click", "clear")
      ] do
    throw <| IO.userError "typed event references did not become mounted bindings"

def run : IO Unit := do
  unless CounterSyntax_declarations.map SurfaceDecl.debug == [
      "state:count", "derived:doubled", "derived:parity",
      "event:increment", "event:addTwo", "event:nestedAddTwo", "event:roundTrip"
    ] do
    throw <| IO.userError "component command declaration inventory changed"
  unless CounterSyntax_declarations.all (fun declaration =>
      !declaration.span.file.isEmpty && declaration.span.start.line > 0 &&
        declaration.span.start.column > 0) do
    throw <| IO.userError "component command did not retain source-linked declarations"
  match CounterSyntax_check with
  | .error error => throw <| IO.userError s!"generated component rejected: {error.code}"
  | .ok checked => verify checked
  unless LeanRxExamples.EchoLab.EchoLab_declarations.map SurfaceDecl.debug == [
      "state:draft", "state:lastKey", "state:note", "derived:summary",
      "event:clear", "event:setDraft", "event:recordKey", "event:commitNote"
    ] do
    throw <| IO.userError "typed component declaration inventory changed"
  match LeanRxExamples.EchoLab.EchoLab_check with
  | .error error => throw <| IO.userError s!"typed component rejected: {error.code}"
  | .ok checked => verifyEcho checked

end LeanRxTest.Elab.Component
