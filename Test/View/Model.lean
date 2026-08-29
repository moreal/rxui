import examples.Counter

namespace LeanRxTest.View.Model

open LeanRx LeanRxExamples.Counter

mutual
  private def ownedAnywhere : MountNode → Bool
    | .element _ attrs children =>
        attrs.contains .ownedState || ownedAnywhereChildren children
    | .text _ | .dynamicText | .child .. | .region _ | .countText _
    | .propText _ => false

  private def ownedAnywhereChildren : MountChildren → Bool
    | .nil => false
    | .cons head tail => ownedAnywhere head || ownedAnywhereChildren tail
end

def run : IO Unit := do
  let split := syntaxView.split
  unless split.textSinks.map (·.name) ==
      ["countText", "doubledText", "parityText", "stableText", "hostileText"] do
    throw <| IO.userError "view split lost or reordered scalar text sinks"
  unless split.textSinks.map (·.path) == [[5, 0], [6, 0], [7, 0], [8, 0], [9, 0]] do
    throw <| IO.userError "view split produced unstable text paths"
  unless split.textSinks.all (fun sink =>
      sink.span.file == "examples/Counter.lean" && sink.span.start.line > 0) do
    throw <| IO.userError "JSX text sinks lost their source locations"
  unless split.events.all (fun mounted =>
      mounted.binding.span.file == "examples/Counter.lean" &&
        mounted.binding.span.start.line > 0) do
    throw <| IO.userError "JSX event bindings lost their source locations"
  unless split.events.map (·.binding.eventName) ==
      ["increment", "addTwo", "nestedAddTwo", "roundTrip"] &&
      split.events.map (·.path) == [[1], [2], [3], [4]] do
    throw <| IO.userError "view split lost or reordered event bindings"
  match split.template with
  | .element .main [.className "counter"] _ => pure ()
  | _ => throw <| IO.userError "view split changed the static mount template"
  -- ADR-0104: the split is where a component-scope element declares that the
  -- program owns its control state, and the law is exactly "carries a
  -- reflected property or a checked selection". Counter reflects nothing, so
  -- its whole mount tree stays silent -- the attribute is never a decoration
  -- on an element that happens to be an input.
  unless ¬ownedAnywhere split.template do
    throw <| IO.userError "an unowned component claimed ownership of control state"
  unless StaticAttr.ownedState.name == "autocomplete" &&
      StaticAttr.ownedState.value == "off" do
    throw <| IO.userError "the owned-state declaration changed its spelling"
  unless StaticAttr.withOwnedState [.className "row"] false == [.className "row"] &&
      StaticAttr.withOwnedState [.className "row"] true ==
        [.className "row", .ownedState] do
    throw <| IO.userError "the owned-state declaration moved out of last position"
  unless (AttrSelect.ownsControlState (Γ := CounterSchema) (.checkedIfEmpty "items")) &&
      ¬(AttrSelect.ownsControlState (Γ := CounterSchema) (.hiddenIfEmpty "items")) do
    throw <| IO.userError "an attribute selection changed what control state it owns"

end LeanRxTest.View.Model
