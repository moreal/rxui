import examples.Counter

namespace LeanRxTest.View.Model

open LeanRx LeanRxExamples.Counter

def run : IO Unit := do
  let split := syntaxView.split
  unless split.textSinks.map (·.name) ==
      ["countText", "doubledText", "parityText", "hostileText"] do
    throw <| IO.userError "view split lost or reordered scalar text sinks"
  unless split.textSinks.map (·.path) == [[4, 0], [5, 0], [6, 0], [7, 0]] do
    throw <| IO.userError "view split produced unstable text paths"
  unless split.textSinks.all (fun sink =>
      sink.span.file == "examples/Counter.lean" && sink.span.start.line > 0) do
    throw <| IO.userError "JSX text sinks lost their source locations"
  unless split.events.all (fun mounted =>
      mounted.binding.span.file == "examples/Counter.lean" &&
        mounted.binding.span.start.line > 0) do
    throw <| IO.userError "JSX event bindings lost their source locations"
  unless split.events.map (·.binding.eventName) == ["increment", "addTwo", "nestedAddTwo"] &&
      split.events.map (·.path) == [[1], [2], [3]] do
    throw <| IO.userError "view split lost or reordered event bindings"
  match split.template with
  | .element .main [.className "counter"] _ => pure ()
  | _ => throw <| IO.userError "view split changed the static mount template"

end LeanRxTest.View.Model
