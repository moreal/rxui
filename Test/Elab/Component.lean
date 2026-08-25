import examples.Counter
import examples.EchoLab
import examples.NestLab

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
      ["setDraft", "recordKey", "commitNote", "toggleLoud"] do
    throw <| IO.userError "typed event declarations lost their names"
  unless checked.spec.typedEvents.toList.map (·.parameterName) ==
      ["value", "value", "value", "checked"] do
    throw <| IO.userError "typed event declarations lost their payload parameters"
  unless checked.spec.typedEvents.toList.map (·.payloadType.debug) ==
      ["string", "string", "string", "bool"] do
    throw <| IO.userError "typed event declarations lost their payload types"
  unless checked.view.events.map
      (fun mounted => (mounted.binding.kind.name, mounted.binding.eventName)) == [
        ("submit", "saveNote"), ("input", "setDraft"), ("keydown", "recordKey"),
        ("change", "toggleLoud"), ("change", "commitNote"), ("click", "clear")
      ] do
    throw <| IO.userError "typed event references did not become mounted bindings"
  unless checked.view.props.map (fun prop => (prop.binding.name, prop.path)) == [
      ("value", [1, 0]), ("checked", [1, 1]), ("value", [2])
    ] do
    throw <| IO.userError "reflected properties did not become mounted prop sinks"

private def verifyNest (checked : CheckedComponent LeanRxExamples.NestLab.NestSchema) :
    IO Unit := do
  unless checked.spec.children.toList.map (·.name) == ["Pulse"] do
    throw <| IO.userError "child component table lost the nested Pulse reference"
  unless checked.spec.children.toList.map (·.moduleSpecifier) == ["./Pulse.mjs"] do
    throw <| IO.userError "child component table lost the module specifier convention"
  unless checked.view.childRefs.map (fun ref => (ref.name, ref.path)) == [("Pulse", [5])] do
    throw <| IO.userError "view split lost the mounted child reference"
  unless checked.view.childRefs.map (·.props) == [[("title", "Pulse child")]] do
    throw <| IO.userError "view split lost the immutable child prop bindings"
  unless checked.spec.regions.toList.map (·.name) == ["roster"] do
    throw <| IO.userError "region table lost the roster declaration"
  unless checked.spec.regions.toList.map (·.fields) == [#["label"]] do
    throw <| IO.userError "region table lost the row field inventory"
  unless checked.spec.regions.toList.map
      (fun region => region.events.toList.map (fun event => (event.name, event.action))) ==
      [[("remove", .remove)]] do
    throw <| IO.userError "region table lost the sealed row event vocabulary"
  unless checked.view.regionRefs.map (fun ref => (ref.name, ref.path)) ==
      [("roster", [4, 0])] do
    throw <| IO.userError "view split lost the mounted region slot"
  match checked.spec.events.toList.find? (·.name == "addItem") with
  | none => throw <| IO.userError "region append event disappeared"
  | some addItem =>
      unless addItem.update.regionAppendTargets == [("roster", 1)] do
        throw <| IO.userError "region append target or arity changed"

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
      "state:draft", "state:lastKey", "state:note", "state:loud", "derived:summary",
      "event:clear", "event:saveNote", "event:setDraft", "event:recordKey",
      "event:commitNote", "event:toggleLoud"
    ] do
    throw <| IO.userError "typed component declaration inventory changed"
  match LeanRxExamples.EchoLab.EchoLab_check with
  | .error error => throw <| IO.userError s!"typed component rejected: {error.code}"
  | .ok checked => verifyEcho checked
  match LeanRxExamples.NestLab.NestLab_check with
  | .error error => throw <| IO.userError s!"nested component rejected: {error.code}"
  | .ok checked => verifyNest checked
  match LeanRxExamples.NestLab.Pulse_check with
  | .error error => throw <| IO.userError s!"child component rejected: {error.code}"
  | .ok checked =>
      unless checked.spec.children.isEmpty && checked.view.childRefs.isEmpty do
        throw <| IO.userError "leaf child component unexpectedly nests children"
      unless checked.spec.propNames == ["title"] do
        throw <| IO.userError "child component lost its immutable prop table"
      unless checked.view.propTexts.map (fun ref => (ref.path, ref.field)) ==
          [([0, 0], 0)] do
        throw <| IO.userError "child view lost its immutable prop text position"

end LeanRxTest.Elab.Component
