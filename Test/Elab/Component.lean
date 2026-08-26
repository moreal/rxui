import examples.BranchLab
import examples.Counter
import examples.EchoLab
import examples.FilterLab
import examples.NestLab
import examples.ToggleLab

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

private def verifyFilter
    (checked : CheckedComponent LeanRxExamples.FilterLab.FilterSchema) : IO Unit := do
  unless checked.view.attrSelects.map (fun mounted =>
      (mounted.select.name, mounted.select.fieldIndex, mounted.select.equals,
        mounted.path)) == [
      ("class", 0, "all", [1, 0]), ("aria-pressed", 0, "all", [1, 0]),
      ("class", 0, "active", [1, 1]), ("aria-pressed", 0, "active", [1, 1]),
      ("class", 0, "completed", [1, 2]), ("aria-pressed", 0, "completed", [1, 2]),
      ("disabled", 0, "all", [2])
    ] do
    throw <| IO.userError "attribute selections did not become mounted selection sinks"
  unless checked.graph.graph.nodes.map (·.name) == #["filter", "filterText",
      "attr:0:class", "attr:1:aria-pressed", "attr:2:class", "attr:3:aria-pressed",
      "attr:4:class", "attr:5:aria-pressed", "attr:6:disabled"] do
    throw <| IO.userError "attribute selections did not join the planned graph"

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
  unless checked.spec.regions.toList.map (·.fields) ==
      [#["label", "marks", "lastKey"]] do
    throw <| IO.userError "region table lost the row field inventory"
  unless checked.spec.regions.toList.map
      (fun region => region.events.toList.map
        (fun event => (event.name, event.action, event.takesPayload))) ==
      [[("remove", .remove, false),
        ("mark", .update [(1, .append (.field 1) (.lit " ★"))], false),
        ("rename", .update [(0, .payload)], true),
        ("record", .update [(2, .append (.lit "key:") .payload)], true)]] do
    throw <| IO.userError "region table lost the sealed row event vocabulary"
  unless checked.spec.regions.toList.map (fun region =>
      match region.template with
      | .element _ _ _ _ _ classIf =>
          classIf.map fun select =>
            (select.field, select.equals, select.whenTrue, select.whenFalse)
      | _ => []) == [[(1, "", "roster-row", "roster-row marked")]] do
    throw <| IO.userError "region table lost the sealed class selection"
  unless checked.view.regionRefs.map (fun ref => (ref.name, ref.path)) ==
      [("roster", [4, 0])] do
    throw <| IO.userError "view split lost the mounted region slot"
  match checked.spec.events.toList.find? (·.name == "addItem") with
  | none => throw <| IO.userError "region append event disappeared"
  | some addItem =>
      unless addItem.update.regionAppendTargets == [("roster", 3)] do
        throw <| IO.userError "region append target or arity changed"

private def verifyBranch
    (checked : CheckedComponent LeanRxExamples.BranchLab.BranchSchema) : IO Unit := do
  unless checked.spec.regions.toList.map (·.fields) ==
      [#["label", "draft", "mode"]] do
    throw <| IO.userError "branch region lost its row field inventory"
  unless checked.spec.regions.toList.map
      (fun region => region.events.toList.map
        (fun event => (event.name, event.action, event.takesPayload))) ==
      [[("remove", .remove, false),
        ("edit", .update [(2, .lit "edit"), (1, .field 0)], false),
        ("retype", .update [(1, .payload)], true),
        ("commit", .update [(0, .field 1), (2, .lit "view")], false)]] do
    throw <| IO.userError "branch region lost the sealed row event vocabulary"
  /- The sealed two-branch cell (ADR-0047): the first cell selects on
  `mode == "view"`, the view branch is the label span, and the edit branch is
  the input reflecting `draft` into its value property. -/
  let cell ← match checked.spec.regions.toList with
    | [region] =>
        match region.template with
        | .element _ _ _ (.cons cell _) _ _ _ => pure cell
        | _ => throw <| IO.userError "branch region lost its row template root"
    | _ => throw <| IO.userError "branch region table changed"
  match cell with
  | .branch field equals whenTrue whenFalse _ =>
      unless field == 2 && equals == "view" do
        throw <| IO.userError "branch cell lost its sealed predicate"
      match whenTrue with
      | .element tag _ _ _ _ _ reflects =>
          unless tag == .span && reflects.isEmpty do
            throw <| IO.userError "branch view subtree changed shape"
      | _ => throw <| IO.userError "branch view subtree is not an element"
      match whenFalse with
      | .element tag _ events _ _ _ reflects autoFocus =>
          unless tag == .input && events.map (·.eventName) == ["retype"] &&
              reflects.map (·.value) == [.field 1] && autoFocus do
            throw <| IO.userError "branch edit subtree lost its binding, reflection, or autoFocus marker"
      | _ => throw <| IO.userError "branch edit subtree is not an element"
  | _ => throw <| IO.userError "the first task cell is not a sealed branch cell"

private def verifyToggle
    (checked : CheckedComponent LeanRxExamples.ToggleLab.ToggleSchema) : IO Unit := do
  unless checked.spec.regions.toList.map (·.fields) ==
      [#["label", "draft", "done", "mode"]] do
    throw <| IO.userError "toggle region lost its row field inventory"
  unless checked.spec.regions.toList.map
      (fun region => region.events.toList.map
        (fun event => (event.name, event.action, event.takesPayload))) ==
      [[("remove", .remove, false),
        ("toggle", .update [(2, .payload)], true),
        ("edit", .update [(3, .lit "edit")], false),
        ("retype", .update [(1, .payload)], true),
        ("commit", .update [(0, .field 1), (3, .lit "view")], false)]] do
    throw <| IO.userError "toggle region lost the sealed row event vocabulary"
  let cells ← match checked.spec.regions.toList with
    | [region] =>
        match region.template with
        | .element _ _ _ cells _ _ _ _ => pure cells.toList
        | _ => throw <| IO.userError "toggle region lost its row template root"
    | _ => throw <| IO.userError "toggle region table changed"
  /- The checkbox cell (ADR-0049): the row-scope `onChange` reference lowered
  to the `checkedChange` binding kind — not the component-scope `change` —
  and `checked={done == "true"}` to the sealed checked reflection. -/
  match cells with
  | checkboxCell :: branchCell :: _ =>
      match checkboxCell with
      | .element _ _ _ (.cons (.element tag attrs events _ _ _ reflects _) _) _ _ _ _ =>
          unless tag == .input && attrs.contains (.inputType .checkbox) &&
              events.map (fun event => (event.kind, event.eventName)) ==
                [(.checkedChange, "toggle")] &&
              reflects.map (fun reflect => (reflect.value, reflect.target)) ==
                [(.field 2, .checkedIf "true")] do
            throw <| IO.userError "toggle checkbox cell lost its binding or checked reflection"
      | _ => throw <| IO.userError "toggle checkbox cell changed shape"
      /- The dblclick edit entry (ADR-0049): both branch subtrees bind the
      same payload-less edit action — click's exact agreement rule. -/
      match branchCell with
      | .branch field equals whenTrue whenFalse _ =>
          unless field == 3 && equals == "view" do
            throw <| IO.userError "toggle branch cell lost its sealed predicate"
          match whenTrue, whenFalse with
          | .element viewTag _ viewEvents _ _ _ _ _,
            .element editTag _ editEvents _ _ _ _ autoFocus =>
              unless viewTag == .span &&
                  viewEvents.map (fun event => (event.kind, event.eventName)) ==
                    [(.dblclick, "edit")] do
                throw <| IO.userError "toggle view subtree lost its dblclick binding"
              unless editTag == .input && autoFocus &&
                  editEvents.map (fun event => (event.kind, event.eventName)) ==
                    [(.input, "retype"), (.dblclick, "edit")] do
                throw <| IO.userError "toggle edit subtree lost its agreed dblclick binding"
          | _, _ => throw <| IO.userError "toggle branch subtrees are not elements"
      | _ => throw <| IO.userError "the second item cell is not a sealed branch cell"
  | _ => throw <| IO.userError "toggle row template lost its cells"
  /- The ADR-0050 broadcast, predicate removal, and sealed count forms: the
  `update`/`remove` event steps lower against the region field inventory and
  the `{count …}` children become mounted count positions in document
  order. -/
  match checked.spec.events.toList.find? (·.name == "completeAll") with
  | none => throw <| IO.userError "toggle broadcast event disappeared"
  | some event =>
      unless event.update.regionBroadcastTargets ==
          [("items", [(2, .lit "true")])] do
        throw <| IO.userError "toggle broadcast lost its target or sealed assignment"
  match checked.spec.events.toList.find? (·.name == "clearCompleted") with
  | none => throw <| IO.userError "toggle removal event disappeared"
  | some event =>
      unless event.update.regionRemoveIfTargets == [("items", 2)] do
        throw <| IO.userError "toggle removal lost its target or predicate field"
  unless checked.view.regionCounts.map
      (fun count => (count.region, count.predicate)) ==
      [("items", some (2, "false")), ("items", none)] do
    throw <| IO.userError "toggle count positions lost their region or predicates"
  /- The ADR-0051 filter view: the `by` state field and the `when` arm table
  lower against the region field inventory — `"all"` carries no arm by
  design, so it is absent from the table. -/
  unless checked.spec.filters.toList.map
      (fun filter => (filter.region, filter.field.index, filter.arms)) ==
      [("items", 1, [("active", 2, "false"), ("completed", 2, "true")])] do
    throw <| IO.userError "toggle filter view lost its state field or arm table"

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
  match LeanRxExamples.FilterLab.FilterLab_check with
  | .error error => throw <| IO.userError s!"filter component rejected: {error.code}"
  | .ok checked => verifyFilter checked
  match LeanRxExamples.NestLab.NestLab_check with
  | .error error => throw <| IO.userError s!"nested component rejected: {error.code}"
  | .ok checked => verifyNest checked
  match LeanRxExamples.BranchLab.BranchLab_check with
  | .error error => throw <| IO.userError s!"branch component rejected: {error.code}"
  | .ok checked => verifyBranch checked
  match LeanRxExamples.ToggleLab.ToggleLab_check with
  | .error error => throw <| IO.userError s!"toggle component rejected: {error.code}"
  | .ok checked => verifyToggle checked
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
