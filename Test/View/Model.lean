import examples.Counter

namespace LeanRxTest.View.Model

open LeanRx LeanRxExamples.Counter

def run : IO Unit := do
  let split := view.split
  unless split.textSinks.map (·.name) ==
      ["countText", "doubledText", "parityText", "hostileText"] do
    throw <| IO.userError "view split lost or reordered scalar text sinks"
  unless split.textSinks.map (·.path) == [[3, 0], [4, 0], [5, 0], [6, 0]] do
    throw <| IO.userError "view split produced unstable text paths"
  unless split.events.map (·.binding.eventName) == ["increment", "addTwo"] &&
      split.events.map (·.path) == [[1], [2]] do
    throw <| IO.userError "view split lost or reordered event bindings"
  match split.template with
  | .element .main [.className "counter"] _ => pure ()
  | _ => throw <| IO.userError "view split changed the static mount template"

end LeanRxTest.View.Model
