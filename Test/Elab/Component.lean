import examples.BranchLab
import examples.Counter
import examples.EchoLab
import examples.FilterLab
import examples.MixLab
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
      (mounted.select.name, mounted.select.fieldIndex?, mounted.select.equals?,
        mounted.path)) == [
      ("class", some 0, some "all", [1, 0]), ("aria-pressed", some 0, some "all", [1, 0]),
      ("class", some 0, some "active", [1, 1]),
      ("aria-pressed", some 0, some "active", [1, 1]),
      ("class", some 0, some "completed", [1, 2]),
      ("aria-pressed", some 0, some "completed", [1, 2]),
      ("disabled", some 0, some "all", [2])
    ] do
    throw <| IO.userError "attribute selections did not become mounted selection sinks"
  unless checked.graph.graph.nodes.map (·.name) == #["filter", "filterText",
      "attr:0:class", "attr:1:aria-pressed", "attr:2:class", "attr:3:aria-pressed",
      "attr:4:class", "attr:5:aria-pressed", "attr:6:disabled"] do
    throw <| IO.userError "attribute selections did not join the planned graph"

/- ADR-0089: a sealed row template composes a *list* of child references —
any number, different components or the same one repeated — so the checked
spec must keep every occurrence in template order with its own prop list,
and the child table must still deduplicate by name. -/
private def verifyMix (checked : CheckedComponent LeanRxExamples.MixLab.MixSchema) :
    IO Unit := do
  unless checked.spec.children.toList.map (·.name) == ["Badge", "Stamp"] do
    throw <| IO.userError "row child table lost its first-occurrence order"
  unless checked.spec.children.toList.map (·.moduleSpecifier) ==
      ["./Badge.mjs", "./Stamp.mjs"] do
    throw <| IO.userError "row child table lost the module specifier convention"
  unless checked.spec.regions.toList.map
      (fun region => region.template.childRefs.map
        (fun (name, props, _) => (name, props))) ==
      [[("Badge", [("tag", .field 2)]),
        ("Stamp", [("mark", .field 0)]),
        ("Stamp", [("mark", .lit "crew stamp")])],
       [("Badge", [("tag", .field 0)])]] do
    throw <| IO.userError "row templates lost their child reference lists"

private def verifyNest (checked : CheckedComponent LeanRxExamples.NestLab.NestSchema) :
    IO Unit := do
  unless checked.spec.children.toList.map (·.name) == ["Chip", "Pulse"] do
    throw <| IO.userError "child component table lost the nested Pulse reference"
  unless checked.spec.children.toList.map (·.moduleSpecifier) ==
      ["./Chip.mjs", "./Pulse.mjs"] do
    throw <| IO.userError "child component table lost the module specifier convention"
  unless checked.view.childRefs.map (fun ref => (ref.name, ref.path)) == [("Pulse", [5])] do
    throw <| IO.userError "view split lost the mounted child reference"
  unless checked.view.childRefs.map (·.props) == [[("title", .lit "Pulse child")]] do
    throw <| IO.userError "view split lost the immutable child prop bindings"
  unless checked.spec.regions.toList.map (·.name) == ["roster"] do
    throw <| IO.userError "region table lost the roster declaration"
  unless checked.spec.regions.toList.map (·.fields) ==
      [#["label", "marks", "lastKey", "origin"]] do
    throw <| IO.userError "region table lost the row field inventory"
  /- ADR-0075: the sealed row template composes one Chip per row, its `tag`
  prop projecting the unwritten `origin` field. -/
  unless checked.spec.regions.toList.map
      (fun region => region.template.childRefs.map
        (fun (name, props, _) => (name, props))) ==
      [[("Chip", [("tag", .field 3)])]] do
    throw <| IO.userError "region table lost the row child reference"
  unless checked.spec.regions.toList.map
      (fun region => region.events.toList.map
        (fun event => (event.name, event.action, event.takesPayload))) ==
      [[("remove", .remove, false),
        ("mark", .update ⟨[(1, .append (.field 1) (.lit " ★"))], none⟩, false),
        ("rename", .update ⟨[(0, .payload)], none⟩, true),
        ("record", .update ⟨[(2, .append (.lit "key:") .payload)], none⟩, true)]] do
    throw <| IO.userError "region table lost the sealed row event vocabulary"
  unless checked.spec.regions.toList.map (fun region =>
      match region.template with
      | .element _ _ _ _ _ classIf =>
          classIf.map fun select =>
            (select.predicate, select.whenTrue, select.whenFalse)
      | _ => []) == [[(.ofField 1 "", "roster-row", "roster-row marked")]] do
    throw <| IO.userError "region table lost the sealed class selection"
  unless checked.view.regionRefs.map (fun ref => (ref.name, ref.path)) ==
      [("roster", [4, 0])] do
    throw <| IO.userError "view split lost the mounted region slot"
  match checked.spec.events.toList.find? (·.name == "addItem") with
  | none => throw <| IO.userError "region append event disappeared"
  | some addItem =>
      unless addItem.update.regionAppendTargets == [("roster", 4)] do
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
        ("edit", .update ⟨[(2, .lit "edit"), (1, .field 0)], none⟩, false),
        ("retype", .update ⟨[(1, .payload)], none⟩, true),
        ("commit", .update ⟨[(0, .field 1), (2, .lit "view")], none⟩, false)]] do
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
        ("toggle", .update ⟨[(2, .payload)], none⟩, true),
        ("edit", .update ⟨[(3, .lit "edit")], none⟩, false),
        ("retype", .update ⟨[(1, .payload)], none⟩, true),
        /- The ADR-0053 remove-if guard on both commit paths, with the
        ADR-0054 trim contract: the guard subject is the trimmed draft and
        the commit assignment stores the trimmed draft —
        destroy-on-empty-commit (whitespace included) through OK and Enter
        alike, while Escape's revert arm stays unguarded and untrimmed. -/
        ("commit", .update ⟨[(0, .trim (.field 1)), (1, .trim (.field 1)),
          (3, .lit "view")], some ⟨.trim (.field 1), ""⟩⟩, false),
        /- The ADR-0052 key-branched selection: `when` arms lower to the
        sealed key table with payload-free right-hand sides, and the event
        is payload-taking — the parameter is the discriminant. -/
        ("keys", .keySelect [
          ("Enter", ⟨[(0, .trim (.field 1)), (1, .trim (.field 1)),
            (3, .lit "view")], some ⟨.trim (.field 1), ""⟩⟩),
          ("Escape", ⟨[(1, .field 0), (3, .lit "view")], none⟩)], true)]] do
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
                    [(.input, "retype"), (.keydown, "keys"), (.dblclick, "edit")] do
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
      unless event.update.regionRemoveIfTargets == [("items", .ofField 2 "true")] do
        throw <| IO.userError "toggle removal lost its target or predicate field"
  unless checked.view.regionCounts.map
      (fun count => (count.region, count.predicate, count.label)) ==
      [("items", some (2, "false"), none),
        ("items", some (2, "false"), some (" item left", " items left")),
        ("items", none, none)] do
    throw <| IO.userError "toggle count positions lost their region, predicates, or label"
  /- The ADR-0051 filter view: the `by` state field and the `when` arm table
  lower against the region field inventory — `"all"` carries no arm by
  design, so it is absent from the table. -/
  unless checked.spec.filters.toList.map
      (fun filter => (filter.region, filter.field.index, filter.arms)) ==
      [("items", 1, [("active", .ofField 2 "false"), ("completed", .ofField 2 "true")])] do
    throw <| IO.userError "toggle filter view lost its state field or arm table"
  /- The ADR-0055 component-scope add path: the controlled new-todo draft is
  the per-keystroke `setDraft` typed event, and `addTodo` carries the sealed
  skip guard — subject the trimmed component draft (state slot 2), the guard
  read in the event summary — with the miss appending one four-field row and
  resetting the draft in the same update. -/
  unless checked.spec.typedEvents.toList.map (·.name) == ["setDraft", "toggleAll"] do
    throw <| IO.userError "toggle typed event inventory changed"
  /- The ADR-0061 payload broadcast: `toggleAll` is the Bool typed event
  whose body is one items broadcast writing the bare checked payload into
  the `done` field — no state target, no state write in its summary. -/
  unless checked.spec.typedEvents.toList.map
      (fun event => (event.broadcast?, event.targetIndex?)) ==
      [(none, some 2), (some ("items", [(2, .payload)]), none)] do
    throw <| IO.userError "toggle payload broadcast lost its body or grew a state target"
  match checked.eventSummaries.toList.find? (·.name == "toggleAll") with
  | none => throw <| IO.userError "toggle payload broadcast summary disappeared"
  | some summary =>
      unless summary.directWrites.isEmpty && summary.directReads.isEmpty &&
          summary.effectiveWrites.isEmpty do
        throw <| IO.userError "toggle payload broadcast summary gained state access"
  match checked.spec.events.toList.find? (·.name == "addTodo") with
  | none => throw <| IO.userError "toggle guarded add event disappeared"
  | some event =>
      unless event.guard?.map (fun guard => (guard.field.index, guard.trimmed)) ==
          some (2, true) do
        throw <| IO.userError "toggle add event lost its skip guard"
      unless event.update.regionAppendTargets == [("items", 4)] do
        throw <| IO.userError "toggle add event lost its append target"
      unless event.update.directWriteTargets == [2] do
        throw <| IO.userError "toggle add event lost its draft reset"
  match checked.eventSummaries.toList.find? (·.name == "addTodo") with
  | none => throw <| IO.userError "toggle add event summary disappeared"
  | some summary =>
      unless summary.directReads == [2] do
        throw <| IO.userError "toggle add event summary lost the guard read"
  /- The ADR-0056 key-branched component event: `confirmAdd` selects on the
  declared `pressed` discriminant with one sealed Enter arm carrying exactly
  the Add button's guarded add — trimmed guard on state slot 2, four-field
  append, draft reset — and its summary unions the arm bodies, guard read
  included. -/
  unless checked.spec.keyEvents.toList.map (fun event =>
      (event.name, event.parameterName, event.arms.map (·.key))) ==
      [("confirmAdd", "pressed", ["Enter", "Escape"])] do
    throw <| IO.userError "toggle key-branched event inventory changed"
  match checked.spec.keyEvents.toList.find? (·.name == "confirmAdd") with
  | none => throw <| IO.userError "toggle key-branched event disappeared"
  | some event =>
      match event.arms with
      | [enterArm, escapeArm] =>
          unless enterArm.guard?.map (fun guard => (guard.field.index, guard.trimmed)) ==
              some (2, true) do
            throw <| IO.userError "toggle Enter arm lost its skip guard"
          unless enterArm.update.regionAppendTargets == [("items", 4)] do
            throw <| IO.userError "toggle Enter arm lost its append target"
          unless enterArm.update.directWriteTargets == [2] do
            throw <| IO.userError "toggle Enter arm lost its draft reset"
          /- The Escape revert arm is unguarded — the sealed Enter/Escape
          component set executed on both keys: an unconditional commit
          writing the empty literal into the draft, nothing else. -/
          unless escapeArm.guard?.isNone do
            throw <| IO.userError "toggle Escape arm grew a guard"
          unless escapeArm.update.regionAppendTargets.isEmpty &&
              escapeArm.update.directWriteTargets == [2] do
            throw <| IO.userError "toggle Escape arm lost its draft revert"
      | _ => throw <| IO.userError "toggle confirmAdd arm table changed"
  match checked.eventSummaries.toList.find? (·.name == "confirmAdd") with
  | none => throw <| IO.userError "toggle key-branched summary disappeared"
  | some summary =>
      unless summary.directReads == [2] && summary.directWrites == [2] do
        throw <| IO.userError "toggle key-branched summary lost the guard read"
  /- The ADR-0057 trimmed disabled selection: the Add button's affordance is
  the ADR-0045 `disabled` selection whose subject sits behind the sealed
  trim unary — the exact trimmed-draft equality the ADR-0055 skip guard
  evaluates, reflected as the boolean element property. The ADR-0058
  empty-region visibility rides beside it: the items list wrapper's
  `hidden` selection carries the region-count subject — no state field, no
  compared string literal — mounted on the `<ul>` that hosts the region.
  The ADR-0059 predicate-count visibility sits between them: the Clear
  completed button's `hidden` selection carries the same region subject
  behind the sealed done-equality predicate. The ADR-0060 toggle-all
  checked selection follows: the static checkbox after the list exports
  the not-done predicate count as its `checked` property. The empty-list
  chrome reuses the ADR-0058 emptiness subject on two more slots without
  any grammar change: the toggle-all box carries `hidden` beside its
  `checked` selection (different attribute names on one element pass
  duplicate detection), and the footer wrapping the items-left line and
  the filter buttons closes the table with the same subject. -/
  unless checked.view.attrSelects.map (fun mounted =>
      (mounted.select.name, mounted.select.fieldIndex?, mounted.select.equals?,
        mounted.select.trimmed, mounted.path)) ==
      [("disabled", some 2, some "", true, [2]),
        ("hidden", none, none, false, [5]),
        ("hidden", none, none, false, [7]),
        ("checked", none, none, false, [8]),
        ("hidden", none, none, false, [8]),
        ("hidden", none, none, false, [9]),
        ("hidden", none, none, false, [10])] do
    throw <| IO.userError "toggle Add affordance lost its trimmed disabled selection"
  unless checked.view.attrSelects.map (·.select.debug) ==
      ["select:disabled:trim:2", "select:hidden:items:2:true",
        "select:hidden:items", "select:checked:items:2:false",
        "select:hidden:items", "select:hidden:items",
        "select:hidden:items:3:edit"] do
    throw <| IO.userError "toggle Add affordance lost its trimmed debug marker"
  unless checked.view.attrSelects.map (fun mounted =>
      (mounted.select.regionSubject?, mounted.select.regionPredicate?,
        mounted.select.hiddenRegion?, mounted.select.checkedRegion?)) ==
      [(none, none, none, none),
        (some "items", some (2, "true"), some "items", none),
        (some "items", none, some "items", none),
        (some "items", some (2, "false"), none, some "items"),
        (some "items", none, some "items", none),
        (some "items", none, some "items", none),
        (some "items", some (3, "edit"), some "items", none)] do
    throw <| IO.userError "toggle list wrapper lost its empty-region visibility subject"
  /- The ADR-0061 toggle-all rebinding: the checkbox's change binding is the
  ADR-0038 `onCheckedChange` surface naming the payload broadcast — the
  delegated checked boolean flows into the broadcast instead of being
  discarded by the ADR-0060 payload-less binding it replaces. -/
  unless checked.view.events.any (fun mounted =>
      mounted.binding.kind == .checkedChange &&
        mounted.binding.eventName == "toggleAll" && mounted.path == [8]) do
    throw <| IO.userError "toggle-all checkbox lost its payload broadcast binding"
  /- The hidden and checked selections are region-driven (ADR-0058/0060):
  like the ADR-0050 count texts they join the region-touch sweep, not the
  planned graph — the graph keeps exactly the sinks it had before. -/
  unless (checked.graph.graph.nodes.map (·.name)).toList.filter
      (fun name => name.startsWith "attr:") == ["attr:0:disabled"] do
    throw <| IO.userError "toggle hidden selection leaked into the planned graph"
  /- The ADR-0063 route item: the sealed `#/`-shaped hash literal set mapped
  one-to-one onto the filter field's existing state literals — the declared
  `"all"` default plus the ADR-0051 filter table — on the filter state slot. -/
  unless checked.spec.routes.toList.map (fun route => (route.field.index, route.arms)) ==
      [(1, [("#/", "all"), ("#/active", "active"), ("#/completed", "completed")])] do
    throw <| IO.userError "toggle route item lost its field or sealed arm table"
  /- The ADR-0063 persist item: one sealed literal storage key targeting the
  declared items region. -/
  unless checked.spec.persists.toList.map (fun persist => (persist.region, persist.key)) ==
      [("items", "leanrx-toggle-lab.items")] do
    throw <| IO.userError "toggle persist item lost its region or sealed storage key"

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
  match LeanRxExamples.MixLab.MixLab_check with
  | .error error => throw <| IO.userError s!"row-child component rejected: {error.code}"
  | .ok checked => verifyMix checked
  match LeanRxExamples.BranchLab.BranchLab_check with
  | .error error => throw <| IO.userError s!"branch component rejected: {error.code}"
  | .ok checked => verifyBranch checked
  match LeanRxExamples.ToggleLab.ToggleLab_check with
  | .error error => throw <| IO.userError s!"toggle component rejected: {error.code}"
  | .ok checked => verifyToggle checked
  match LeanRxExamples.NestLab.Pulse_check with
  | .error error => throw <| IO.userError s!"child component rejected: {error.code}"
  | .ok checked =>
      /- ADR-0067: the intermediate child composes its own child through the
      same table and reference shapes as the root component. -/
      unless checked.spec.children.toList.map (·.name) == ["Tick"] do
        throw <| IO.userError "intermediate child component lost its child table"
      unless checked.spec.children.toList.map (·.moduleSpecifier) == ["./Tick.mjs"] do
        throw <| IO.userError "intermediate child component lost its child module specifier"
      unless checked.view.childRefs.map (fun ref => (ref.name, ref.path)) ==
          [("Tick", [3])] do
        throw <| IO.userError "intermediate child component lost its grandchild reference"
      /- ADR-0068: `label={title}` forwards the parent's own immutable prop
      by declaration index; the reference carries the forward, not a
      literal. -/
      unless checked.view.childRefs.map (·.props) == [[("label", .forward 0)]] do
        throw <| IO.userError "intermediate child component lost its grandchild prop forward"
      unless checked.spec.propNames == ["title"] do
        throw <| IO.userError "child component lost its immutable prop table"
      unless checked.view.propTexts.map (fun ref => (ref.path, ref.field)) ==
          [([0, 0], 0)] do
        throw <| IO.userError "child view lost its immutable prop text position"
  match LeanRxExamples.NestLab.Tick_check with
  | .error error => throw <| IO.userError s!"grandchild component rejected: {error.code}"
  | .ok checked =>
      /- ADR-0069: the grandchild re-forwards the prop it received — the
      forwarding rewrite reads the declared prop inventory only, never the
      source of the parent's value, so the reference shape is identical to
      the ADR-0068 first-level forward. ADR-0070: the same received prop
      fans out into a second leaf — the child table and references scale by
      declaration order, each entry carrying its own `.forward` index.
      ADR-0071: composing the same child module twice dedups the table by
      name only — `childRefs` keeps every occurrence, each reference
      carrying its own independent `ChildProp` list (one forward, one
      literal). -/
      unless checked.spec.children.toList.map (·.name) == ["Blip", "Chip"] do
        throw <| IO.userError "grandchild component lost its child table"
      unless checked.spec.children.toList.map (·.moduleSpecifier) ==
          ["./Blip.mjs", "./Chip.mjs"] do
        throw <| IO.userError "grandchild component lost its child module specifier"
      unless checked.view.childRefs.map (fun ref => (ref.name, ref.path)) ==
          [("Blip", [3]), ("Chip", [4]), ("Chip", [5])] do
        throw <| IO.userError "grandchild component lost its great-grandchild reference"
      unless checked.view.childRefs.map (·.props) ==
          [[("note", .forward 0)], [("tag", .forward 0)], [("tag", .lit "fixed chip")]] do
        throw <| IO.userError "grandchild component lost its great-grandchild prop forward"
      unless checked.spec.propNames == ["label"] do
        throw <| IO.userError "grandchild component lost its immutable prop table"
      unless checked.view.propTexts.map (fun ref => (ref.path, ref.field)) ==
          [([0, 0], 0)] do
        throw <| IO.userError "grandchild view lost its immutable prop text position"
  match LeanRxExamples.NestLab.Blip_check with
  | .error error => throw <| IO.userError s!"great-grandchild component rejected: {error.code}"
  | .ok checked =>
      unless checked.spec.children.isEmpty && checked.view.childRefs.isEmpty do
        throw <| IO.userError "leaf great-grandchild component unexpectedly nests children"
      unless checked.spec.propNames == ["note"] do
        throw <| IO.userError "great-grandchild component lost its immutable prop table"
      unless checked.view.propTexts.map (fun ref => (ref.path, ref.field)) ==
          [([0, 0], 0)] do
        throw <| IO.userError "great-grandchild view lost its immutable prop text position"
  match LeanRxExamples.NestLab.Chip_check with
  | .error error => throw <| IO.userError s!"fan-out leaf component rejected: {error.code}"
  | .ok checked =>
      /- ADR-0070: the second fan-out leaf is a plain leaf — no nesting, one
      immutable prop rendered at the same structural position as Blip's. -/
      unless checked.spec.children.isEmpty && checked.view.childRefs.isEmpty do
        throw <| IO.userError "fan-out leaf component unexpectedly nests children"
      unless checked.spec.propNames == ["tag"] do
        throw <| IO.userError "fan-out leaf component lost its immutable prop table"
      unless checked.view.propTexts.map (fun ref => (ref.path, ref.field)) ==
          [([0, 0], 0)] do
        throw <| IO.userError "fan-out leaf view lost its immutable prop text position"

end LeanRxTest.Elab.Component
