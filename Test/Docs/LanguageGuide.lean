import LeanRx

namespace LeanRxTest.Docs.LanguageGuide

open LeanRx

abbrev CounterSchema : Schema :=
  .field "count" Int <| .field "label" String .empty

def count : Field CounterSchema Int := .here
def label : Field CounterSchema String := .there .here

def doubled := RxExpr.binary .intMul
  (RxExpr.read count)
  (RxExpr.literal (.int 2))

def countText := RxExpr.binary .stringAppend
  (RxExpr.literal (.string "Count: "))
  (RxExpr.unary .intToString (RxExpr.read count))

def values : Array (ValueSpec CounterSchema) := #[
  ValueSpec.state count (.int 1),
  ValueSpec.computed label countText
]

def increment : EventSpec CounterSchema :=
  { name := "increment"
    update := .set count <| RxExpr.binary .intAdd
      (RxExpr.read count) (RxExpr.literal (.int 1)) }

def counterView : View CounterSchema := View.node .main [
  View.node .h1 [.text "Counter"],
  View.node .button [.text "Increment"]
    (attrs := [.buttonType .button])
    (events := [{ kind := .click, eventName := "increment" }]),
  View.node .p [.scalarText "countText" countText]
]

def spec : ComponentSpec CounterSchema :=
  { name := "Counter"
    values
    events := #[increment]
    view := counterView }

def checked := spec.check

open scoped LeanRxDsl

component CounterSyntax (schema := CounterSchema) where {
  state count : Int := 1;
  derived label := rx% s!"Count: {count}";
  event increment := set count (count + 1);
  view := jsx% <main> [
    <h1> ["Counter"],
    <button type="button" onClick={increment}> ["Increment"],
    <p> [{"countText": rx% s!"Count: {count}"}]
  ];
}

/- The explicit right-hand sides remain valid alongside the sugared items. -/
component CounterExplicitSyntax (schema := CounterSchema) where {
  state count := ValueSpec.state count (.int 1);
  derived label := ValueSpec.computed label countText;
  event increment := increment;
  view := counterView;
}

/- The controlled-input snippet from guide section 7 (ADR-0038). -/
abbrev EchoMiniSchema : Schema :=
  .field "draft" String <| .field "loud" Bool .empty

def draft : Field EchoMiniSchema String := .here
def loud : Field EchoMiniSchema Bool := .there .here

component EchoMini (schema := EchoMiniSchema) where {
  state draft : String := "";
  state loud : Bool := false;
  event save := set draft "";
  event setDraft (value : String) := set draft value;
  event toggleLoud (checked : Bool) := set loud checked;
  view := jsx% <main> [
    <form onSubmit={save}> [
      <input ariaLabel="Draft" value={rx% draft} onInput={setDraft} />,
      <input ariaLabel="Loud" type="checkbox" checked={rx% loud} onCheckedChange={toggleLoud} />,
      <button type="submit"> ["Save"]
    ]
  ];
}

/- The static child-nesting snippet from guide section 7 (ADR-0039). -/
abbrev NestMiniSchema : Schema := .field "clicks" Int .empty

def clicks : Field NestMiniSchema Int := .here

component NestMini (schema := NestMiniSchema) where {
  state clicks : Int := 0;
  event bump := set clicks (clicks + 1);
  view := jsx% <main> [
    <button type="button" onClick={bump}> ["Bump"],
    <EchoMini/>
  ];
}

/- The keyed region snippet from guide section 7 (ADR-0040/0041). -/
abbrev RosterMiniSchema : Schema := .field "added" Int .empty

def added : Field RosterMiniSchema Int := .here

component RosterMini (schema := RosterMiniSchema) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}") then set added (added + 1);
  region roster (label) := jsx% <li> [
    <span> [{label}],
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}

/- The row-update and class-selection snippet from guide section 7
(ADR-0043/0044). -/
abbrev MarkedRosterMiniSchema : Schema := .field "markedAdded" Int .empty

def markedAdded : Field MarkedRosterMiniSchema Int := .here

component MarkedRosterMini (schema := MarkedRosterMiniSchema) where {
  state markedAdded : Int := 0;
  event addItem := append roster (s!"Item {markedAdded}", "")
    then set markedAdded (markedAdded + 1);
  row roster mark := set marks (marks ++ " ★");
  region roster (label, marks) := jsx%
    <li class={if marks == "" then "row" else "row marked"}> [
      <span> [{label ++ marks}],
      <span> [<button type="button" ariaLabel="Mark" onClick={mark}> ["★"]],
      <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
    ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}

/- The typed row payload snippet from guide section 7 (ADR-0046). -/
abbrev EditableRosterMiniSchema : Schema := .field "editAdded" Int .empty

def editAdded : Field EditableRosterMiniSchema Int := .here

component EditableRosterMini (schema := EditableRosterMiniSchema) where {
  state editAdded : Int := 0;
  event addItem := append roster (s!"Item {editAdded}", "")
    then set editAdded (editAdded + 1);
  row roster rename (value : String) := set label value;
  row roster record (pressed : String) := set lastKey ("key:" ++ pressed);
  region roster (label, lastKey) := jsx% <li> [
    <span> [{label}],
    <span> [{lastKey}],
    <span> [<input ariaLabel="Rename" onInput={rename} onKeyDown={record} />],
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}

/- The two-branch row cell, value reflection, and autoFocus snippet from
guide section 7 (ADR-0047/0048). -/
abbrev BranchRosterMiniSchema : Schema := .field "branchAdded" Int .empty

def branchAdded : Field BranchRosterMiniSchema Int := .here

component BranchRosterMini (schema := BranchRosterMiniSchema) where {
  state branchAdded : Int := 0;
  event addItem := append roster (s!"Item {branchAdded}", s!"Item {branchAdded}", "view")
    then set branchAdded (branchAdded + 1);
  row roster edit := set mode "edit" then set draft label;
  row roster retype (value : String) := set draft value;
  row roster commit := set label draft then set mode "view";
  region roster (label, draft, mode) := jsx% <li> [
    {if mode == "view"
      then <span> [{label}]
      else <input ariaLabel="Editor" value={draft} onInput={retype} autoFocus/>},
    <span> [<button type="button" ariaLabel="Edit" onClick={edit}> ["Edit"]],
    <span> [<button type="button" ariaLabel="Commit" onClick={commit}> ["OK"]],
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}

/- The delegated dblclick and checkbox change snippet from guide section 7
(ADR-0049). -/
abbrev ToggleRosterMiniSchema : Schema := .field "toggleAdded" Int .empty

def toggleAdded : Field ToggleRosterMiniSchema Int := .here

component ToggleRosterMini (schema := ToggleRosterMiniSchema) where {
  state toggleAdded : Int := 0;
  event addItem := append roster (s!"Item {toggleAdded}", "false", "view")
    then set toggleAdded (toggleAdded + 1);
  row roster toggle (checked : String) := set done checked;
  row roster edit := set mode "edit";
  row roster commit := set mode "view";
  region roster (label, done, mode) := jsx% <li> [
    <span> [<input type="checkbox" ariaLabel="Done" checked={done == "true"}
      onChange={toggle}/>],
    {if mode == "view"
      then <span onDblClick={edit}> [{label}]
      else <input ariaLabel="Editor" value={label} onDblClick={edit} autoFocus/>},
    <span> [<button type="button" ariaLabel="Commit" onClick={commit}> ["OK"]],
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}

/- The sealed count, broadcast, and predicate-removal snippet from guide
section 7 (ADR-0050). -/
abbrev CountedRosterMiniSchema : Schema := .field "countedAdded" Int .empty

def countedAdded : Field CountedRosterMiniSchema Int := .here

component CountedRosterMini (schema := CountedRosterMiniSchema) where {
  state countedAdded : Int := 0;
  event addItem := append roster (s!"Item {countedAdded}", "false")
    then set countedAdded (countedAdded + 1);
  event completeAll := update roster (set done "true");
  event clearCompleted := remove roster (done == "true");
  event toggleAll (checked : Bool) := update roster (set done checked);
  row roster toggle (checked : String) := set done checked;
  region roster (label, done) := jsx% <li> [
    <span> [<input type="checkbox" ariaLabel="Done" checked={done == "true"}
      onChange={toggle}/>],
    <span> [{label}]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <button type="button" onClick={completeAll}> ["Complete all"],
    <button type="button" onClick={clearCompleted}
      hidden={count roster (done == "true") == 0}> ["Clear completed"],
    <p> [<strong> [{count roster (done == "false")}],
      {if count roster (done == "false") == 1 then " item left" else " items left"},
      " of ", {count roster}],
    <ul ariaLabel="Items" hidden={count roster == 0}> [<region roster/>],
    <input type="checkbox" ariaLabel="Toggle all"
      checked={count roster (done == "false") == 0} onCheckedChange={toggleAll}/>
  ];
}

/- The sealed region filter view snippet from guide section 7 (ADR-0051). -/
abbrev FilteredRosterMiniSchema : Schema :=
  .field "filteredAdded" Int <| .field "shown" String .empty

def filteredAdded : Field FilteredRosterMiniSchema Int := .here
def shown : Field FilteredRosterMiniSchema String := .there .here

component FilteredRosterMini (schema := FilteredRosterMiniSchema) where {
  state filteredAdded : Int := 0;
  state shown : String := "all";
  event addItem := append roster (s!"Item {filteredAdded}", "false")
    then set filteredAdded (filteredAdded + 1);
  event showAll := set shown "all";
  event showActive := set shown "active";
  filter roster by shown := when "active" (done == "false")
    then when "completed" (done == "true");
  row roster toggle (checked : String) := set done checked;
  region roster (label, done) := jsx% <li> [
    <span> [<input type="checkbox" ariaLabel="Done" checked={done == "true"}
      onChange={toggle}/>],
    <span> [{label}]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <button type="button" onClick={showAll}> ["Show all"],
    <button type="button" onClick={showActive}> ["Show active"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}

/- The key-branched row event snippet from guide section 7 (ADR-0052). -/
abbrev KeyedEditorMiniSchema : Schema := .field "keyedAdded" Int .empty

def keyedAdded : Field KeyedEditorMiniSchema Int := .here

component KeyedEditorMini (schema := KeyedEditorMiniSchema) where {
  state keyedAdded : Int := 0;
  event addItem := append roster (s!"Item {keyedAdded}", s!"Item {keyedAdded}", "view")
    then set keyedAdded (keyedAdded + 1);
  row roster edit := set mode "edit";
  row roster retype (value : String) := set draft value;
  row roster keys (pressed : String) := when "Enter" (set label draft, set mode "view")
    then when "Escape" (set draft label, set mode "view");
  region roster (label, draft, mode) := jsx% <li> [
    {if mode == "view"
      then <span onDblClick={edit}> [{label}]
      else <input ariaLabel="Editor" value={draft} onInput={retype}
        onKeyDown={keys} onDblClick={edit} autoFocus/>}
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}

/- The guarded row event snippet from guide section 7 (ADR-0053/0054). -/
abbrev GuardedEditorMiniSchema : Schema := .field "guardedAdded" Int .empty

def guardedAdded : Field GuardedEditorMiniSchema Int := .here

component GuardedEditorMini (schema := GuardedEditorMiniSchema) where {
  state guardedAdded : Int := 0;
  event addItem := append roster (s!"Item {guardedAdded}", s!"Item {guardedAdded}", "view")
    then set guardedAdded (guardedAdded + 1);
  row roster edit := set mode "edit";
  row roster retype (value : String) := set draft value;
  row roster commit := if trim draft == "" then remove
    else (set label (trim draft), set mode "view");
  row roster keys (pressed : String) :=
    when "Enter" (if trim draft == "" then remove
      else (set label (trim draft), set mode "view"))
    then when "Escape" (set draft label, set mode "view");
  region roster (label, draft, mode) := jsx% <li> [
    {if mode == "view"
      then <span onDblClick={edit}> [{label}]
      else <input ariaLabel="Editor" value={draft} onInput={retype}
        onKeyDown={keys} onDblClick={edit} autoFocus/>},
    <span> [<button type="button" ariaLabel="OK" onClick={commit}> ["OK"]]
  ];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}

/- The skip-guarded component event snippet from guide section 7
(ADR-0055), with the ADR-0056 key-branched Enter confirmation and the
ADR-0057 trimmed disabled affordance. -/
abbrev NewTodoMiniSchema : Schema := .field "newTodoDraft" String .empty

def newTodoDraft : Field NewTodoMiniSchema String := .here

component NewTodoMini (schema := NewTodoMiniSchema) where {
  state newTodoDraft : String := "";
  event add := if trim newTodoDraft == "" then skip
    else (append roster (trim newTodoDraft), set newTodoDraft "");
  event setDraft (value : String) := set newTodoDraft value;
  event confirm (pressed : String) :=
    when "Enter" (if trim newTodoDraft == "" then skip
      else (append roster (trim newTodoDraft), set newTodoDraft ""));
  region roster (label) := jsx% <li> [
    <span> [{label}],
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["✕"]]
  ];
  view := jsx% <main> [
    <input ariaLabel="New todo" value={rx% newTodoDraft} onInput={setDraft}
      onKeyDown={confirm}/>,
    <button type="button" onClick={add}
      disabled={trim newTodoDraft == ""}> ["Add"],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}

/- The state-scoped attribute selection snippet from guide section 7
(ADR-0045). -/
abbrev FilterMiniSchema : Schema := .field "filter" String .empty

def filter : Field FilterMiniSchema String := .here

component FilterMini (schema := FilterMiniSchema) where {
  state filter : String := "all";
  event showAll := set filter "all";
  event showActive := set filter "active";
  view := jsx% <main> [
    <button type="button" onClick={showAll}
        class={if filter == "all" then "selected" else ""}
        ariaPressed={filter == "all"}> ["All"],
    <button type="button" onClick={showActive}
        class={if filter == "active" then "selected" else ""}
        ariaPressed={filter == "active"}> ["Active"],
    <button type="button" onClick={showAll} disabled={filter == "all"}> ["Reset"]
  ];
}

/- The immutable-prop snippets from guide section 7 (ADR-0042). -/
abbrev TitledMiniSchema : Schema := .field "titledClicks" Int .empty

def titledClicks : Field TitledMiniSchema Int := .here

component TitledMini (schema := TitledMiniSchema) where {
  state titledClicks : Int := 0;
  prop title : String;
  event bump := set titledClicks (titledClicks + 1);
  view := jsx% <main> [
    <h1> [{title}],
    <button type="button" onClick={bump}> ["Bump"]
  ];
}

abbrev PropNestMiniSchema : Schema := .field "hosts" Int .empty

def hosts : Field PropNestMiniSchema Int := .here

component PropNestMini (schema := PropNestMiniSchema) where {
  state hosts : Int := 0;
  event host := set hosts (hosts + 1);
  view := jsx% <main> [
    <button type="button" onClick={host}> ["Host"],
    <TitledMini title="Hello"/>
  ];
}

def run : IO Unit := do
  unless doubled.dependencies.ids == [0] && countText.dependencies.ids == [0] do
    throw <| IO.userError "language-guide expression dependencies changed"
  match checked, CounterSyntax_check with
  | .ok explicit, .ok generated =>
      unless explicit.graph.graph.nodes.map (·.name) ==
          generated.graph.graph.nodes.map (·.name) do
        throw <| IO.userError "language-guide explicit and scoped graphs diverged"
  | .error error, _ | _, .error error =>
      throw <| IO.userError s!"language-guide component rejected: {error.render}"
  match CounterExplicitSyntax_check with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError s!"language-guide explicit component rejected: {error.render}"
  match EchoMini_check with
  | .ok controlled =>
      unless controlled.view.props.map (·.binding.name) == ["value", "checked"] do
        throw <| IO.userError "language-guide controlled snippet lost its reflections"
  | .error error =>
      throw <| IO.userError s!"language-guide controlled component rejected: {error.render}"
  match NestMini_check with
  | .ok nested =>
      unless nested.spec.children.toList.map (·.name) == ["EchoMini"] do
        throw <| IO.userError "language-guide nesting snippet lost its child table"
  | .error error =>
      throw <| IO.userError s!"language-guide nested component rejected: {error.render}"
  match RosterMini_check with
  | .ok roster =>
      unless roster.spec.regions.toList.map (·.name) == ["roster"] &&
          roster.view.regionRefs.map (·.name) == ["roster"] do
        throw <| IO.userError "language-guide region snippet lost its region table"
  | .error error =>
      throw <| IO.userError s!"language-guide region component rejected: {error.render}"
  match MarkedRosterMini_check with
  | .ok marked =>
      unless marked.spec.regions.toList.map
          (fun region => region.events.toList.map (·.name)) == [["remove", "mark"]] do
        throw <| IO.userError "language-guide row-update snippet lost its event table"
  | .error error =>
      throw <| IO.userError s!"language-guide row-update component rejected: {error.render}"
  match EditableRosterMini_check with
  | .ok editable =>
      unless editable.spec.regions.toList.map
          (fun region => region.events.toList.map
            (fun event => (event.name, event.takesPayload))) ==
          [[("remove", false), ("rename", true), ("record", true)]] do
        throw <| IO.userError "language-guide payload snippet lost its event table"
  | .error error =>
      throw <| IO.userError s!"language-guide payload component rejected: {error.render}"
  match BranchRosterMini_check with
  | .ok branching =>
      let cell? := branching.spec.regions.toList.head?.bind fun region =>
        match region.template with
        | .element _ _ _ (.cons cell _) _ _ _ => some cell
        | _ => none
      match cell? with
      | some (.branch field equals _ whenFalse _) =>
          unless field == 2 && equals == "view" do
            throw <| IO.userError "language-guide branch snippet lost its predicate"
          match whenFalse with
          | .element _ _ _ _ _ _ _ autoFocus =>
              unless autoFocus do
                throw <| IO.userError "language-guide branch snippet lost its autoFocus marker"
          | _ => throw <| IO.userError "language-guide branch snippet lost its edit branch"
      | _ => throw <| IO.userError "language-guide branch snippet lost its branch cell"
  | .error error =>
      throw <| IO.userError s!"language-guide branch component rejected: {error.render}"
  match ToggleRosterMini_check with
  | .ok toggling =>
      unless toggling.spec.regions.toList.map
          (fun region => region.events.toList.map
            (fun event => (event.name, event.takesPayload))) ==
          [[("remove", false), ("toggle", true), ("edit", false),
            ("commit", false)]] do
        throw <| IO.userError "language-guide toggle snippet lost its event table"
      let cells? := toggling.spec.regions.toList.head?.bind fun region =>
        match region.template with
        | .element _ _ _ cells _ _ _ _ => some cells.toList
        | _ => none
      match cells? with
      | some (checkboxCell :: branchCell :: _) =>
          match checkboxCell with
          | .element _ _ _ (.cons (.element _ _ events _ _ _ reflects _) _) _ _ _ _ =>
              unless events.map (·.kind) == [.checkedChange] &&
                  reflects.map (·.target) == [.checkedIf "true"] do
                throw <| IO.userError
                  "language-guide toggle snippet lost its change binding or checked reflection"
          | _ => throw <| IO.userError "language-guide toggle snippet lost its checkbox cell"
          match branchCell with
          | .branch _ _ whenTrue whenFalse _ =>
              unless [whenTrue, whenFalse].all (fun subtree =>
                  match subtree with
                  | .element _ _ events _ _ _ _ _ =>
                      events.any fun event =>
                        event.kind == .dblclick && event.eventName == "edit"
                  | _ => false) do
                throw <| IO.userError
                  "language-guide toggle snippet lost its agreed dblclick bindings"
          | _ => throw <| IO.userError "language-guide toggle snippet lost its branch cell"
      | _ => throw <| IO.userError "language-guide toggle snippet lost its cells"
  | .error error =>
      throw <| IO.userError s!"language-guide toggle component rejected: {error.render}"
  match CountedRosterMini_check with
  | .ok counting =>
      unless counting.view.regionCounts.map
          (fun count => (count.region, count.predicate, count.label)) ==
          [("roster", some (1, "false"), none),
            ("roster", some (1, "false"), some (" item left", " items left")),
            ("roster", none, none)] do
        throw <| IO.userError "language-guide count snippet lost its count positions"
      unless counting.spec.events.toList.map
          (fun event => (event.name,
            event.update.regionBroadcastTargets, event.update.regionRemoveIfTargets)) ==
          [("addItem", [], []),
            ("completeAll", [("roster", [(1, .lit "true")])], []),
            ("clearCompleted", [], [("roster", 1)])] do
        throw <| IO.userError
          "language-guide count snippet lost its broadcast or removal steps"
      unless counting.view.attrSelects.map (fun mounted =>
          (mounted.select.name, mounted.select.regionSubject?,
            mounted.select.regionPredicate?, mounted.path)) ==
          [("hidden", some "roster", some (1, "true"), [2]),
            ("hidden", some "roster", none, [4]),
            ("checked", some "roster", some (1, "false"), [5])] do
        throw <| IO.userError
          "language-guide count snippet lost its empty-region visibility selection"
      /- The ADR-0061 payload broadcast: the toggle-all box's checked payload
      flows into the roster broadcast as a bare set right-hand side. -/
      unless counting.spec.typedEvents.toList.map
          (fun event => (event.name, event.broadcast?, event.targetIndex?)) ==
          [("toggleAll", some ("roster", [(1, .payload)]), none)] do
        throw <| IO.userError
          "language-guide count snippet lost its payload broadcast"
  | .error error =>
      throw <| IO.userError s!"language-guide count component rejected: {error.render}"
  match FilteredRosterMini_check with
  | .ok filtered =>
      unless filtered.spec.filters.toList.map
          (fun filter => (filter.region, filter.field.index, filter.arms)) ==
          [("roster", 1, [("active", 1, "false"), ("completed", 1, "true")])] do
        throw <| IO.userError
          "language-guide filter snippet lost its state field or arm table"
  | .error error =>
      throw <| IO.userError s!"language-guide filter component rejected: {error.render}"
  match KeyedEditorMini_check with
  | .ok keyed =>
      unless keyed.spec.regions.toList.map (fun region =>
          region.events.toList.map fun event =>
            (event.name, event.action, event.takesPayload)) ==
          [[("remove", .remove, false),
            ("edit", .update ⟨[(2, .lit "edit")], none⟩, false),
            ("retype", .update ⟨[(1, .payload)], none⟩, true),
            ("keys", .keySelect [
              ("Enter", ⟨[(0, .field 1), (2, .lit "view")], none⟩),
              ("Escape", ⟨[(1, .field 0), (2, .lit "view")], none⟩)], true)]] do
        throw <| IO.userError
          "language-guide key-branch snippet lost its sealed arm table"
  | .error error =>
      throw <| IO.userError s!"language-guide key-branch component rejected: {error.render}"
  match GuardedEditorMini_check with
  | .ok guarded =>
      unless guarded.spec.regions.toList.map (fun region =>
          region.events.toList.map fun event =>
            (event.name, event.action, event.takesPayload)) ==
          [[("remove", .remove, false),
            ("edit", .update ⟨[(2, .lit "edit")], none⟩, false),
            ("retype", .update ⟨[(1, .payload)], none⟩, true),
            ("commit", .update ⟨[(0, .trim (.field 1)), (2, .lit "view")],
              some ⟨.trim (.field 1), ""⟩⟩, false),
            ("keys", .keySelect [
              ("Enter", ⟨[(0, .trim (.field 1)), (2, .lit "view")],
                some ⟨.trim (.field 1), ""⟩⟩),
              ("Escape", ⟨[(1, .field 0), (2, .lit "view")], none⟩)], true)]] do
        throw <| IO.userError
          "language-guide guarded snippet lost its remove-if guards"
  | .error error =>
      throw <| IO.userError s!"language-guide guarded component rejected: {error.render}"
  match NewTodoMini_check with
  | .ok adding =>
      unless adding.spec.events.toList.map (fun event =>
          (event.name,
            event.guard?.map fun guard => (guard.field.index, guard.trimmed))) ==
          [("add", some (0, true))] do
        throw <| IO.userError "language-guide skip-guard snippet lost its guard"
      unless (adding.spec.events.toList.map (·.update.regionAppendTargets)) ==
          [[("roster", 1)]] do
        throw <| IO.userError "language-guide skip-guard snippet lost its append"
      unless adding.spec.keyEvents.toList.map (fun event =>
          (event.name, event.arms.map fun arm =>
            (arm.key, arm.guard?.map fun guard =>
              (guard.field.index, guard.trimmed)))) ==
          [("confirm", [("Enter", some (0, true))])] do
        throw <| IO.userError "language-guide key-branch snippet lost its arm table"
      unless adding.view.attrSelects.map (fun mounted =>
          (mounted.select.name, mounted.select.fieldIndex?,
            mounted.select.equals?, mounted.select.trimmed)) ==
          [("disabled", some 0, some "", true)] do
        throw <| IO.userError
          "language-guide trimmed affordance snippet lost its selection"
  | .error error =>
      throw <| IO.userError s!"language-guide skip-guard component rejected: {error.render}"
  match FilterMini_check with
  | .ok selecting =>
      unless selecting.view.attrSelects.map (·.select.name) ==
          ["class", "aria-pressed", "class", "aria-pressed", "disabled"] do
        throw <| IO.userError "language-guide selection snippet lost its selections"
  | .error error =>
      throw <| IO.userError s!"language-guide selection component rejected: {error.render}"
  match TitledMini_check, PropNestMini_check with
  | .ok titled, .ok host =>
      unless titled.spec.propNames == ["title"] &&
          host.view.childRefs.map (·.props) == [[("title", "Hello")]] do
        throw <| IO.userError "language-guide prop snippets lost their bindings"
  | .error error, _ | _, .error error =>
      throw <| IO.userError s!"language-guide prop component rejected: {error.render}"

end LeanRxTest.Docs.LanguageGuide
