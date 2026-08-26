import LeanRx.Component.Model
import LeanRx.Elab.Rx
import LeanRx.Elab.View
import Lean.Elab.Command
import Lean.Meta.Eval

open Lean Elab Command Term Meta

/-! The `component` command surface.

Items dispatch on a leading plain identifier (`state`, `derived`, `event`,
`view`) instead of reserved keyword atoms, so opening the DSL scope never
removes those words from the identifier namespace (ADR-0035). Right-hand
sides accept both the explicit `ValueSpec`/`EventSpec` terms and the sugared
forms `state name : Type := literal`, `derived name := rx% …`, and
`event name := set field (expr) then …` (ADR-0036); event references inside
an inline `jsx%` view (`onClick={name}`) are checked against the declared
event inventory and lowered to the same string bindings. -/

namespace LeanRxDsl

private def normalizedFileName : CommandElabM String := do
  let fileName ← getFileName
  let currentDir ← IO.currentDir
  let rootPrefix := currentDir.toString ++ "/"
  pure <| if fileName.startsWith rootPrefix then
    (fileName.drop rootPrefix.length).toString
  else fileName

private def sourceSpanTerm (stx : Syntax) : CommandElabM (TSyntax `term) := do
  let fileMap ← getFileMap
  let fileName := Syntax.mkStrLit (← normalizedFileName)
  let start := stx.getPos?.getD 0
  let stop := stx.getTailPos?.getD start
  let startPosition := fileMap.toPosition start
  let stopPosition := fileMap.toPosition stop
  let startLine := Syntax.mkNumLit (toString startPosition.line)
  let startColumn := Syntax.mkNumLit (toString (startPosition.column + 1))
  let startByte := Syntax.mkNumLit (toString start.byteIdx)
  let stopLine := Syntax.mkNumLit (toString stopPosition.line)
  let stopColumn := Syntax.mkNumLit (toString (stopPosition.column + 1))
  let stopByte := Syntax.mkNumLit (toString stop.byteIdx)
  `(LeanRx.SourceSpan.mk $fileName
      (LeanRx.SourcePos.mk $startLine $startColumn $startByte)
      (LeanRx.SourcePos.mk $stopLine $stopColumn $stopByte))

declare_syntax_cat leanrxComponentItem
scoped syntax (name := leanrxItemTypedEvent)
  atomic(ident ident "(" ident ":" ident ")" ":=") term ";" : leanrxComponentItem
scoped syntax (name := leanrxItemTypedState)
  atomic(ident ident ":" ident ":=") term ";" : leanrxComponentItem
scoped syntax (name := leanrxItemProp)
  atomic(ident ident ":" ident ";") : leanrxComponentItem
scoped syntax (name := leanrxItemRegion)
  atomic(ident ident "(" ident,* ")" ":=") term ";" : leanrxComponentItem
scoped syntax (name := leanrxItemRowEvent)
  atomic(ident ident ident ":=") sepBy1(term, " then ") ";" : leanrxComponentItem
scoped syntax (name := leanrxItemRowTypedEvent)
  atomic(ident ident ident "(" ident ":" ident ")" ":=")
    sepBy1(term, " then ") ";" : leanrxComponentItem
scoped syntax (name := leanrxItemFilter)
  atomic(ident ident "by" ident ":=") sepBy1(term, " then ") ";" : leanrxComponentItem
scoped syntax (name := leanrxItemValue)
  atomic(ident ident ":=") sepBy1(term, " then ") ";" : leanrxComponentItem
scoped syntax (name := leanrxItemView)
  atomic(ident ":=") term ";" : leanrxComponentItem

open scoped LeanRxDsl

/-- Elaborate one component value right-hand side by its staged type: explicit
`ValueSpec` terms pass through; a staged `rx%` expression is wrapped into the
derived value for the declaration's schema field. -/
elab "leanrx_component_value% " field:ident value:term : term <= expectedType => do
  let valueType ← withoutModifyingState <| Term.withoutErrToSorry do
    let expression ← Term.elabTerm value none
    Term.synthesizeSyntheticMVarsNoPostponing
    whnf (← instantiateMVars (← inferType expression))
  if valueType.isAppOf ``LeanRx.RxExpr then
    Term.elabTerm (← `(LeanRx.ValueSpec.computed $field $value)) expectedType
  else
    Term.elabTerm value expectedType

private def roleName (role : Ident) : String :=
  role.getId.eraseMacroScopes.toString

private def checkRole (role : Ident) : CommandElabM String := do
  let name := roleName role
  unless ["state", "derived", "event", "view", "region", "row", "prop",
      "filter"].contains name do
    throwErrorAt role
      s!"error[LRX-ELAB-003]: unknown component item role {name}; expected state, derived, event, region, row, prop, filter, or view"
  pure name

private def scalarLiteralTerm (ty : Ident) (value : TSyntax `term) :
    CommandElabM (TSyntax `term) := do
  match ty.getId.eraseMacroScopes.toString with
  | "Int" => `(LeanRx.ScalarLiteral.int $value)
  | "Nat" => `(LeanRx.ScalarLiteral.nat $value)
  | "Bool" => `(LeanRx.ScalarLiteral.bool $value)
  | "String" => `(LeanRx.ScalarLiteral.string $value)
  | other => throwErrorAt ty
      s!"error[LRX-ELAB-105]: state literals support Int, Nat, Bool, and String, not {other}"

private def eventAttrNames : List Name :=
  [`onClick, `onDblClick, `onInput, `onKeyDown, `onChange, `onCheckedChange, `onSubmit]

/-- Rewrite `onClick={declaredEvent}` (and the typed payload attributes) inside
an inline view to the checked string binding when the identifier names an event
declared by this component; other references keep their term-level lowering. -/
private partial def rewriteEventRefs (events : List String) (stx : Syntax) : Syntax :=
  match stx with
  | .node info kind args =>
      if kind == ``LeanRxDsl.leanrxJsxAttrDynamic && args.size == 5 then
        let attrName := args[0]!
        let value := args[3]!
        if attrName.isIdent && eventAttrNames.contains attrName.getId.eraseMacroScopes &&
            value.isIdent && events.contains value.getId.eraseMacroScopes.toString then
          let eventLit := Syntax.mkStrLit value.getId.eraseMacroScopes.toString
            (info := value.getHeadInfo)
          .node info ``LeanRxDsl.leanrxJsxAttrNamed #[attrName, args[1]!, eventLit]
        else
          .node info kind (args.map (rewriteEventRefs events))
      else
        .node info kind (args.map (rewriteEventRefs events))
  | _ => stx

private def sepByElems (stx : Syntax) : Array Syntax :=
  (Array.range ((stx.getNumArgs + 1) / 2)).map fun index => stx[2 * index]

/-- Rewrite `{propName}` children of an inline view to the internal
`propText% index` child when the identifier names a declared immutable prop
(ADR-0042). -/
private partial def rewritePropRefs (props : List String) (stx : Syntax) : Syntax :=
  match stx with
  | .node info kind args =>
      if kind == ``LeanRxDsl.leanrxJsxChildDynamic && args.size == 3 &&
          args[1]!.isIdent then
        match props.idxOf? (args[1]!.getId.eraseMacroScopes.toString) with
        | some index =>
            let ref := args[1]!.getHeadInfo
            .node info ``LeanRxDsl.leanrxJsxPropText
              #[.atom ref "propText%", Syntax.mkNumLit (toString index) (info := ref)]
        | none => .node info kind (args.map (rewritePropRefs props))
      else
        .node info kind (args.map (rewritePropRefs props))
  | _ => stx

private def renderFields (fields : List String) : String :=
  String.intercalate ", " fields

/-- Rewrite `{count region}` and `{count region (field == "literal")}`
children of an inline view to the internal `regionCount%` child (ADR-0050).
The `count` head with an argument is claimed by the rewrite — unnamed dynamic
text is rejected downstream either way, so the shape cannot collide with a
legitimate child — and the predicate field resolves against the region's
declared field inventory here, where the inventory exists. -/
private partial def rewriteCountRefs (regionFields : List (String × List String))
    (stx : Syntax) : CommandElabM Syntax := do
  let countChild? (value : TSyntax `term) :
      CommandElabM (Option (TSyntax `leanrxJsxChild)) := do
    let resolve (region : TSyntax `ident) : CommandElabM (List String) := do
      let name := region.getId.eraseMacroScopes.toString
      match regionFields.find? (·.1 == name) with
      | some entry => pure entry.2
      | none =>
          throwErrorAt region
            s!"error[LRX-ELAB-119]: count references unknown region {name}"
    match value with
    | `($head:ident $region:ident) =>
        if head.getId.eraseMacroScopes == `count then
          let _ ← resolve region
          let regionLit := Syntax.mkStrLit region.getId.eraseMacroScopes.toString
          pure (some (← `(leanrxJsxChild| regionCount% $regionLit:str)))
        else pure none
    | `($head:ident $region:ident ($field:ident == $lit:str)) =>
        if head.getId.eraseMacroScopes == `count then
          let fields ← resolve region
          let fieldName := field.getId.eraseMacroScopes.toString
          let index ← match fields.idxOf? fieldName with
            | some index => pure index
            | none =>
                throwErrorAt field
                  s!"error[LRX-ELAB-119]: unknown row field {fieldName}; declared fields are {renderFields fields}"
          let regionLit := Syntax.mkStrLit region.getId.eraseMacroScopes.toString
          let indexLit := Syntax.mkNumLit (toString index)
          pure (some (← `(leanrxJsxChild| regionCount% $regionLit:str $indexLit:num $lit:str)))
        else pure none
    | _ => pure none
  match stx with
  | .node info kind args =>
      if kind == ``LeanRxDsl.leanrxJsxChildDynamic && args.size == 3 then
        match ← countChild? ⟨args[1]!⟩ with
        | some child => pure child.raw
        | none => pure (.node info kind (← args.mapM (rewriteCountRefs regionFields)))
      else
        pure (.node info kind (← args.mapM (rewriteCountRefs regionFields)))
  | _ => pure stx

private def rowAttrTerm (attr : Syntax) : CommandElabM (TSyntax `term) := do
  let attrStx : TSyntax `leanrxJsxAttr := ⟨attr⟩
  match attrStx with
  | `(leanrxJsxAttr| $_:ident = { $_:term }) =>
      throwErrorAt attr
        "error[LRX-ELAB-114]: row templates support static attributes and row event references only"
  | `(leanrxJsxAttr| type = { $_:term }) =>
      throwErrorAt attr
        "error[LRX-ELAB-114]: row templates support static attributes and row event references only"
  | _ => `(leanrx_jsx_attr% $attrStx)

/-- Lower one sealed row expression (ADR-0043): bare row fields, string
literals, and `++` concatenation — nothing else enters row scope. Inside a
typed row event right-hand side (ADR-0046), `payload?` names the declared
payload parameter, which lowers to `RowExpr.payload`. -/
private partial def rowExprTerm (fields : List String) (payload? : Option String)
    (value : TSyntax `term) : CommandElabM (TSyntax `term) := do
  match value with
  | `($first:term ++ $second:term) => do
      let firstTerm ← rowExprTerm fields payload? first
      let secondTerm ← rowExprTerm fields payload? second
      `(LeanRx.RowExpr.append $firstTerm $secondTerm)
  | `(($inner:term)) => rowExprTerm fields payload? inner
  | `($lit:str) => `(LeanRx.RowExpr.lit $lit)
  | `($name:ident) =>
      let text := name.getId.eraseMacroScopes.toString
      if payload? == some text then
        `(LeanRx.RowExpr.payload)
      else match fields.idxOf? text with
      | some index =>
          let indexLit := Syntax.mkNumLit (toString index)
          `(LeanRx.RowExpr.field $indexLit)
      | none =>
          throwErrorAt value
            s!"error[LRX-ELAB-115]: unknown row field {name.getId.eraseMacroScopes}; declared fields are {renderFields fields}"
  | _ =>
      throwErrorAt value
        "error[LRX-ELAB-115]: row expressions are row fields, string literals, and ++"

/-- Lower one sealed class selection (ADR-0044):
`class={if field == "literal" then "a" else "b"}`. -/
private def rowClassSelectTerm (fields : List String) (attr : Syntax)
    (value : TSyntax `term) : CommandElabM (TSyntax `term) := do
  match value with
  | `(if $field:ident == $lit:str then $whenTrue:str else $whenFalse:str) =>
      match fields.idxOf? field.getId.eraseMacroScopes.toString with
      | some index =>
          let indexLit := Syntax.mkNumLit (toString index)
          let span ← sourceSpanTerm attr
          `(LeanRx.RowClassSelect.mk $indexLit $lit $whenTrue $whenFalse $span)
      | none =>
          throwErrorAt field
            s!"error[LRX-ELAB-116]: unknown row field {field.getId.eraseMacroScopes}; declared fields are {renderFields fields}"
  | _ =>
      throwErrorAt attr
        "error[LRX-ELAB-116]: a row class selection is written class=\{if field == \"literal\" then \"whenTrue\" else \"whenFalse\"}"

/- Lower one sealed row template (ADR-0041): dynamic content is restricted to
declared row field projections, and events were already rewritten to string
bindings against the sealed row event vocabulary. -/
mutual
  private partial def lowerRowChild (fields : List String) (child : Syntax) :
      CommandElabM (TSyntax `term) := do
    let childStx : TSyntax `leanrxJsxChild := ⟨child⟩
    match childStx with
    | `(leanrxJsxChild| $value:str) => do
        let span ← sourceSpanTerm child
        `(LeanRx.RowNode.text $value $span)
    | `(leanrxJsxChild| { $value:term }) => do
        let span ← sourceSpanTerm child
        if value.raw.isIdent then
          match fields.idxOf? (value.raw.getId.eraseMacroScopes.toString) with
          | some index =>
              let indexLit := Syntax.mkNumLit (toString index)
              `(LeanRx.RowNode.fieldText $indexLit $span)
          | none =>
              throwErrorAt child
                s!"error[LRX-ELAB-114]: unknown row field {value.raw.getId.eraseMacroScopes}; declared fields are {String.intercalate ", " fields}"
        else
          /- Sealed row expression content (ADR-0043). -/
          let expr ← rowExprTerm fields none value
          `(LeanRx.RowNode.exprText $expr $span)
    | `(leanrxJsxChild| { $_:str : $_:term }) =>
        throwErrorAt child
          "error[LRX-ELAB-114]: named text sinks are not available inside row templates"
    | `(leanrxJsxChild| { if $field:ident == $lit:str then $whenTrue:leanrxJsxElement
          else $whenFalse:leanrxJsxElement }) => do
        /- The sealed two-branch row cell (ADR-0047): one row field equality
        selects between two statically sealed template subtrees. -/
        let span ← sourceSpanTerm child
        match fields.idxOf? (field.getId.eraseMacroScopes.toString) with
        | some index =>
            let indexLit := Syntax.mkNumLit (toString index)
            let whenTrueTerm ← lowerRowElement fields whenTrue
            let whenFalseTerm ← lowerRowElement fields whenFalse
            `(LeanRx.RowNode.branch $indexLit $lit $whenTrueTerm $whenFalseTerm $span)
        | none =>
            throwErrorAt field
              s!"error[LRX-ELAB-118]: unknown row field {field.getId.eraseMacroScopes}; declared fields are {renderFields fields}"
    | `(leanrxJsxChild| $element:leanrxJsxElement) => lowerRowElement fields element
    | _ =>
        throwErrorAt child
          "error[LRX-ELAB-114]: malformed row template child"

  /- A `class={…}` attribute lowers to the sealed class selection (ADR-0044),
  a `value={…}` attribute to the sealed value reflection (ADR-0047), a
  `checked={field == "literal"}` attribute to the sealed checked reflection
  (ADR-0049), an `onChange={name}` reference to the delegated checkbox
  `change` binding (ADR-0049), and the bare `autoFocus` marker to the sealed
  focus marker (ADR-0048); everything else stays a static attribute or row
  event reference. -/
  private partial def lowerRowAttrs (fields : List String) (attrs : Array Syntax) :
      CommandElabM
        (Array (TSyntax `term) × Array (TSyntax `term) × Array (TSyntax `term) × Bool) := do
    let mut attrTerms : Array (TSyntax `term) := #[]
    let mut selectTerms : Array (TSyntax `term) := #[]
    let mut reflectTerms : Array (TSyntax `term) := #[]
    let mut autoFocus := false
    for attr in attrs do
      let attrStx : TSyntax `leanrxJsxAttr := ⟨attr⟩
      match attrStx with
      | `(leanrxJsxAttr| class = { $value:term }) =>
          selectTerms := selectTerms.push (← rowClassSelectTerm fields attr value)
      | `(leanrxJsxAttr| value = { $value:term }) => do
          let exprTerm ← rowExprTerm fields none value
          let span ← sourceSpanTerm attr
          reflectTerms := reflectTerms.push (← `(LeanRx.RowReflect.mk $exprTerm .value $span))
      | `(leanrxJsxAttr| checked = { $field:ident == $lit:str }) => do
          /- The sealed row checked reflection (ADR-0049): the checkbox
          `checked` property follows equality of one projected row field
          against one literal — the ADR-0045 `disabled` shape in row scope. -/
          let index ← match fields.idxOf? (field.getId.eraseMacroScopes.toString) with
            | some index => pure index
            | none =>
                throwErrorAt field
                  s!"error[LRX-ELAB-115]: unknown row field {field.getId.eraseMacroScopes}; declared fields are {renderFields fields}"
          let indexLit := Syntax.mkNumLit (toString index)
          let span ← sourceSpanTerm attr
          reflectTerms := reflectTerms.push
            (← `(LeanRx.RowReflect.mk (LeanRx.RowExpr.field $indexLit)
              (.checkedIf $lit) $span))
      | `(leanrxJsxAttr| checked = { $_:term }) =>
          throwErrorAt attr
            "error[LRX-VIEW-037]: a row checked reflection is written checked=\{field == \"literal\"} (ADR-0049)"
      | `(leanrxJsxAttr| onChange = $event:str) => do
          /- Row-scope `onChange` is the delegated checkbox binding
          (ADR-0049): the delegated `checked` boolean lowers to the
          `"true"`/`"false"` string payload, so the binding kind is
          `checkedChange`, not the component-scope `value`-payload
          `change`. -/
          attrTerms := attrTerms.push (← `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.checkedChange, eventName := $event }))
      | `(leanrxJsxAttr| $name:ident) =>
          if name.getId.eraseMacroScopes == `autoFocus then do
            if autoFocus then
              throwErrorAt name "error[LRX-VIEW-036]: element carries duplicate autoFocus markers"
            autoFocus := true
          else
            throwErrorAt name
              s!"error[LRX-VIEW-008]: unknown or invalid view attribute {name.getId.eraseMacroScopes}"
      | _ => attrTerms := attrTerms.push (← rowAttrTerm attr)
    pure (attrTerms, selectTerms, reflectTerms, autoFocus)

  private partial def lowerRowElement (fields : List String)
      (element : TSyntax `leanrxJsxElement) : CommandElabM (TSyntax `term) := do
    match element with
    | `(leanrxJsxElement| <$tag:ident $attrs:leanrxJsxAttr* >
          [$children:leanrxJsxChild,*]) => do
        let (attrTerms, selectTerms, reflectTerms, autoFocus) ← lowerRowAttrs fields attrs
        let childTerms ← children.getElems.mapM (lowerRowChild fields ·)
        let span ← sourceSpanTerm element
        let focusTerm ← if autoFocus then `(Bool.true) else `(Bool.false)
        `(LeanRx.RowNode.nodeWith (leanrx_jsx_tag% $tag) [$childTerms,*]
          (attrs := [$attrTerms,*]) (span := $span) (classIf := [$selectTerms,*])
          (reflects := [$reflectTerms,*]) (autoFocus := $focusTerm))
    | `(leanrxJsxElement| <$tag:ident $attrs:leanrxJsxAttr* />) => do
        let (attrTerms, selectTerms, reflectTerms, autoFocus) ← lowerRowAttrs fields attrs
        let span ← sourceSpanTerm element
        let focusTerm ← if autoFocus then `(Bool.true) else `(Bool.false)
        `(LeanRx.RowNode.nodeWith (leanrx_jsx_tag% $tag) []
          (attrs := [$attrTerms,*]) (span := $span) (classIf := [$selectTerms,*])
          (reflects := [$reflectTerms,*]) (autoFocus := $focusTerm))
    | _ =>
        throwErrorAt element
          "error[LRX-ELAB-111]: a region item takes an inline jsx% row template element"
end

/-- Elaborate one `prop name : String;` item to its `PropSpec` (ADR-0042). -/
private def elabPropItem (item : Syntax) (itemSpan : TSyntax `term) :
    CommandElabM (TSyntax `term) := do
  let role : Ident := ⟨item[0]⟩
  let itemName : Ident := ⟨item[1]⟩
  let ty : Ident := ⟨item[3]⟩
  let roleName ← checkRole role
  unless roleName == "prop" do
    throwErrorAt role
      s!"error[LRX-ELAB-003]: value-less type annotations are valid only on prop items, not {roleName}"
  unless ty.getId.eraseMacroScopes.toString == "String" do
    throwErrorAt ty
      s!"error[LRX-ELAB-113]: immutable props support String, not {ty.getId.eraseMacroScopes}"
  let nameLit := Syntax.mkStrLit itemName.getId.eraseMacroScopes.toString
  `(LeanRx.PropSpec.mk $nameLit $itemSpan)

/-- The declared row field inventory of every region item, for row-event and
row-expression elaboration (ADR-0043). -/
private def collectRegionFields (items : Array Syntax) : List (String × List String) :=
  items.foldl (init := []) fun acc item =>
    if item.getKind == ``leanrxItemRegion then
      let itemName : Ident := ⟨item[1]⟩
      let fields := (sepByElems item[3]).toList.map fun field =>
        (⟨field⟩ : Ident).getId.eraseMacroScopes.toString
      acc ++ [(itemName.getId.eraseMacroScopes.toString, fields)]
    else acc

/-- Resolve one `row` item's region and field inventory, shared by the
payload-less and typed forms. -/
private def rowEventContext (regionFields : List (String × List String))
    (role regionName eventName : Ident) : CommandElabM (String × List String) := do
  let roleName ← checkRole role
  unless roleName == "row" do
    throwErrorAt role
      s!"error[LRX-ELAB-003]: two-name items are valid only on row items, not {roleName}"
  let region := regionName.getId.eraseMacroScopes.toString
  match regionFields.find? (·.1 == region) with
  | some entry => pure (region, entry.2)
  | none =>
      throwErrorAt regionName
        s!"error[LRX-ELAB-115]: row event {eventName.getId.eraseMacroScopes} references unknown region {region}"

/-- Lower `set field (expr) then …` row event steps to their sealed update
assignments (ADR-0043); `payload?` admits the typed payload parameter in the
right-hand sides (ADR-0046). -/
private def rowUpdateAssignments (fields : List String) (payload? : Option String)
    (steps : Array (TSyntax `term)) : CommandElabM (Array (TSyntax `term)) := do
  let mut assignments : Array (TSyntax `term) := #[]
  for step in steps do
    match step with
    | `($head:ident $field:ident $value:term) =>
        unless head.getId.eraseMacroScopes == `set do
          throwErrorAt step "error[LRX-ELAB-115]: row event steps are `set field (expr)`"
        let fieldName := field.getId.eraseMacroScopes.toString
        let index ← match fields.idxOf? fieldName with
          | some index => pure index
          | none =>
              throwErrorAt field
                s!"error[LRX-ELAB-115]: unknown row field {fieldName}; declared fields are {renderFields fields}"
        let indexLit := Syntax.mkNumLit (toString index)
        let exprTerm ← rowExprTerm fields payload? value
        assignments := assignments.push (← `(($indexLit, $exprTerm)))
    | _ => throwErrorAt step "error[LRX-ELAB-115]: row event steps are `set field (expr)`"
  pure assignments

/-- Interpret one sugared event step (`set field (expr)`, `dispatch event`,
`append region (expr, …)`, `update region (set field (expr), …)`, or
`remove region (field == "literal")`) as its explicit `Update` constructor;
any other shape is not a step. The `update` and `remove` heads are the
ADR-0050 region broadcast and predicate removal: their inner assignments and
predicates are sealed row expressions elaborated against the target region's
declared field inventory. -/
private def updateStepTerm? (regionFields : List (String × List String))
    (step : TSyntax `term) : CommandElabM (Option (TSyntax `term)) := do
  match step with
  | `($head:ident $field:ident $value:term) =>
      if head.getId.eraseMacroScopes == `set then
        pure (some (← `(LeanRx.Update.set $field (rx% $value))))
      else if head.getId.eraseMacroScopes == `append then
        let regionLit := Syntax.mkStrLit field.getId.eraseMacroScopes.toString
        let values ← match value with
          | `(($first:term, $rest:term,*)) => pure (#[first] ++ rest.getElems)
          | _ => pure #[value]
        let rowValues ← values.mapM fun fieldValue =>
          `(LeanRx.RowValue.of (rx% $fieldValue))
        pure (some (← `(LeanRx.Update.regionAppend $regionLit [$rowValues,*])))
      else if head.getId.eraseMacroScopes == `update then
        let region := field.getId.eraseMacroScopes.toString
        let fields ← match regionFields.find? (·.1 == region) with
          | some entry => pure entry.2
          | none =>
              throwErrorAt field
                s!"error[LRX-ELAB-119]: broadcast step references unknown region {region}"
        let steps ← match value with
          | `(($first:term, $rest:term,*)) => pure (#[first] ++ rest.getElems)
          | `(($inner:term)) => pure #[inner]
          | _ =>
              throwErrorAt value
                "error[LRX-ELAB-119]: a region broadcast is written `update region (set field (expr), …)`"
        let assignments ← rowUpdateAssignments fields none steps
        let regionLit := Syntax.mkStrLit region
        pure (some (← `(LeanRx.Update.regionBroadcast $regionLit [$assignments,*])))
      else if head.getId.eraseMacroScopes == `remove then
        let region := field.getId.eraseMacroScopes.toString
        let fields ← match regionFields.find? (·.1 == region) with
          | some entry => pure entry.2
          | none =>
              throwErrorAt field
                s!"error[LRX-ELAB-119]: removal step references unknown region {region}"
        match value with
        | `(($predField:ident == $lit:str)) =>
            let fieldName := predField.getId.eraseMacroScopes.toString
            let index ← match fields.idxOf? fieldName with
              | some index => pure index
              | none =>
                  throwErrorAt predField
                    s!"error[LRX-ELAB-119]: unknown row field {fieldName}; declared fields are {renderFields fields}"
            let indexLit := Syntax.mkNumLit (toString index)
            let regionLit := Syntax.mkStrLit region
            pure (some (← `(LeanRx.Update.regionRemoveIf $regionLit $indexLit $lit)))
        | _ =>
            throwErrorAt value
              "error[LRX-ELAB-119]: a region removal is written `remove region (field == \"literal\")`"
      else pure none
  | `($head:ident $target:ident) =>
      if head.getId.eraseMacroScopes == `dispatch then
        let targetLit := Syntax.mkStrLit target.getId.eraseMacroScopes.toString
        pure (some (← `(LeanRx.Update.dispatch $targetLit)))
      else pure none
  | _ => pure none

/-- Elaborate one `row region event := set field (expr) then …;` item to its
region name, event name, and sealed `RowEventSpec` (ADR-0043). -/
private def elabRowEventItem (regionFields : List (String × List String))
    (item : Syntax) (itemSpan : TSyntax `term) :
    CommandElabM (String × String × TSyntax `term) := do
  let eventName : Ident := ⟨item[2]⟩
  let (region, fields) ← rowEventContext regionFields ⟨item[0]⟩ ⟨item[1]⟩ eventName
  let steps := (sepByElems item[4]).map fun step => (⟨step⟩ : TSyntax `term)
  let assignments ← rowUpdateAssignments fields none steps
  let nameLit := Syntax.mkStrLit eventName.getId.eraseMacroScopes.toString
  pure (region, eventName.getId.eraseMacroScopes.toString,
    ← `(LeanRx.RowEventSpec.mk $nameLit (LeanRx.RowAction.update [$assignments,*])
        false $itemSpan))

/-- Elaborate one typed `row region event (param : String) := set field (expr)
then …;` item (ADR-0046): the payload parameter enters the sealed row
expression scope of the right-hand sides and the spec is marked
payload-taking. -/
private def elabRowTypedEventItem (regionFields : List (String × List String))
    (item : Syntax) (itemSpan : TSyntax `term) :
    CommandElabM (String × String × TSyntax `term) := do
  let eventName : Ident := ⟨item[2]⟩
  let param : Ident := ⟨item[4]⟩
  let ty : Ident := ⟨item[6]⟩
  let (region, fields) ← rowEventContext regionFields ⟨item[0]⟩ ⟨item[1]⟩ eventName
  unless ty.getId.eraseMacroScopes.toString == "String" do
    throwErrorAt ty
      s!"error[LRX-ELAB-117]: typed row event payloads support String, not {ty.getId.eraseMacroScopes}"
  let paramName := param.getId.eraseMacroScopes.toString
  if fields.contains paramName then
    throwErrorAt param
      s!"error[LRX-ELAB-117]: payload parameter {paramName} shadows a row field of region {region}"
  let steps := (sepByElems item[9]).map fun step => (⟨step⟩ : TSyntax `term)
  let assignments ← rowUpdateAssignments fields (some paramName) steps
  let nameLit := Syntax.mkStrLit eventName.getId.eraseMacroScopes.toString
  pure (region, eventName.getId.eraseMacroScopes.toString,
    ← `(LeanRx.RowEventSpec.mk $nameLit (LeanRx.RowAction.update [$assignments,*])
        true $itemSpan))

/-- Elaborate one `filter region by field := when "literal" (rowField ==
"literal") then …;` item to its `RegionFilter` (ADR-0051): each arm maps one
distinct state literal to one row-field equality predicate, and a state
value outside the table shows every row — TodoMVC's `all` needs no arm. -/
private def elabFilterItem (regionFields : List (String × List String))
    (item : Syntax) (itemSpan : TSyntax `term) : CommandElabM (TSyntax `term) := do
  let role : Ident := ⟨item[0]⟩
  let regionName : Ident := ⟨item[1]⟩
  let fieldName : Ident := ⟨item[3]⟩
  let roleName ← checkRole role
  unless roleName == "filter" do
    throwErrorAt role
      s!"error[LRX-ELAB-003]: `by` state selectors are valid only on filter items, not {roleName}"
  let region := regionName.getId.eraseMacroScopes.toString
  let fields ← match regionFields.find? (·.1 == region) with
    | some entry => pure entry.2
    | none =>
        throwErrorAt regionName
          s!"error[LRX-ELAB-120]: filter view references unknown region {region}"
  let steps := (sepByElems item[5]).map fun step => (⟨step⟩ : TSyntax `term)
  let mut arms : Array (TSyntax `term) := #[]
  for step in steps do
    match step with
    | `($head:ident $stateLit:str ($rowField:ident == $rowLit:str)) =>
        unless head.getId.eraseMacroScopes == `when do
          throwErrorAt step
            "error[LRX-ELAB-120]: a filter arm is written `when \"literal\" (field == \"literal\")`"
        let rowFieldName := rowField.getId.eraseMacroScopes.toString
        let index ← match fields.idxOf? rowFieldName with
          | some index => pure index
          | none =>
              throwErrorAt rowField
                s!"error[LRX-ELAB-120]: unknown row field {rowFieldName}; declared fields are {renderFields fields}"
        let indexLit := Syntax.mkNumLit (toString index)
        arms := arms.push (← `(($stateLit, $indexLit, $rowLit)))
    | _ =>
        throwErrorAt step
          "error[LRX-ELAB-120]: a filter arm is written `when \"literal\" (field == \"literal\")`"
  let regionLit := Syntax.mkStrLit region
  `(LeanRx.RegionFilter.mk $regionLit $fieldName [$arms,*] $itemSpan)

/-- Elaborate one `region name (fields) := jsx% …;` item to its `RegionSpec`
(ADR-0041). Every region declares the sealed `remove` row event plus its `row`
item update events (ADR-0043); templates opt in by binding `onClick={name}`. -/
private def elabRegionItem (item : Syntax) (itemSpan : TSyntax `term)
    (rowEvents : List (String × String × TSyntax `term)) :
    CommandElabM (TSyntax `term) := do
  let role : Ident := ⟨item[0]⟩
  let itemName : Ident := ⟨item[1]⟩
  let fields := sepByElems item[3] |>.map fun field => (⟨field⟩ : Ident)
  let rhs : TSyntax `term := ⟨item[6]⟩
  let roleName ← checkRole role
  unless roleName == "region" do
    throwErrorAt role
      s!"error[LRX-ELAB-003]: row field lists are valid only on region items, not {roleName}"
  let fieldNames := fields.map (·.getId.eraseMacroScopes.toString)
  let regionName := itemName.getId.eraseMacroScopes.toString
  let nameLit := Syntax.mkStrLit regionName
  let extras := rowEvents.filter (·.1 == regionName)
  let extraNames := extras.map (·.2.1)
  let extraTerms : Array (TSyntax `term) := (extras.map (·.2.2)).toArray
  let template ← match rhs with
    | `(jsx% $element:leanrxJsxElement) =>
        let rewritten : TSyntax `leanrxJsxElement :=
          ⟨rewriteEventRefs ("remove" :: extraNames) element.raw⟩
        lowerRowElement fieldNames.toList rewritten
    | _ =>
        throwErrorAt rhs
          "error[LRX-ELAB-111]: a region item takes an inline jsx% row template"
  let fieldLits : Array (TSyntax `term) :=
    fieldNames.map fun fieldName => ⟨Syntax.mkStrLit fieldName⟩
  `(LeanRx.RegionSpec.mk $nameLit #[$fieldLits,*] $template
    #[LeanRx.RowEventSpec.mk "remove" LeanRx.RowAction.remove false $itemSpan,
      $extraTerms,*]
    $itemSpan)

private def literalPropAttr? (attr : TSyntax `leanrxJsxAttr) : Bool :=
  match attr with
  | `(leanrxJsxAttr| $_:ident = $_:str) => true
  | _ => false

/-- The head identifier of one child-less JSX element whose attributes are all
`name="text"` — the only shapes that can lower to a static child component
reference, without (ADR-0039) or with (ADR-0042) immutable props. -/
private def childElementHead? (stx : Syntax) : Option (TSyntax `ident) :=
  let element : TSyntax `leanrxJsxElement := ⟨stx⟩
  match element with
  | `(leanrxJsxElement| <$tag:ident $attrs:leanrxJsxAttr* />) =>
      if attrs.all literalPropAttr? then some tag else none
  | `(leanrxJsxElement| <$tag:ident $attrs:leanrxJsxAttr* > [$children:leanrxJsxChild,*]) =>
      if attrs.all literalPropAttr? && children.getElems.isEmpty then some tag else none
  | _ => none

/-- Collect every capitalized head that the inline view could lower to a
`View.child` reference, in first-occurrence order. -/
private partial def collectComponentHeads (stx : Syntax)
    (found : Array (TSyntax `ident) := #[]) : Array (TSyntax `ident) :=
  let found := match childElementHead? stx with
    | some tag => if componentHead? tag then found.push tag else found
    | none => found
  match stx with
  | .node _ _ args => args.foldl (init := found) fun acc arg => collectComponentHeads arg acc
  | _ => found

/- The single command elaborator now dispatches nine item kinds; compiling
its one large match needs more than the default heartbeat budget. -/
set_option maxHeartbeats 800000 in
scoped elab (name := leanrxComponent) "component" name:ident "(" "schema" ":=" schemaTerm:term ")"
    "where" "{" items:leanrxComponentItem* "}" : command => do
      /- First pass: the declared event and immutable prop inventories, so an
      inline view can bind events and prop text positions by reference before
      the specification value exists. -/
      let mut declaredEvents : List String := []
      let mut declaredProps : List String := []
      for item in items do
        match item with
        | `(leanrxComponentItem| $role:ident $itemName:ident
              ($_:ident : $_:ident) := $_:term;) =>
            if roleName role == "event" then
              declaredEvents := declaredEvents ++ [itemName.getId.eraseMacroScopes.toString]
        | _ =>
            if item.raw.getKind == ``leanrxItemProp then
              let role : Ident := ⟨item.raw[0]⟩
              if roleName role == "prop" then
                let itemName : Ident := ⟨item.raw[1]⟩
                declaredProps := declaredProps ++ [itemName.getId.eraseMacroScopes.toString]
            else if item.raw.getKind == ``leanrxItemValue then
              let role : Ident := ⟨item.raw[0]⟩
              if roleName role == "event" then
                let itemName : Ident := ⟨item.raw[1]⟩
                declaredEvents := declaredEvents ++ [itemName.getId.eraseMacroScopes.toString]
      /- Row-event pre-pass (ADR-0043): `row` items elaborate against the
      region field inventory and join their region's sealed event table, so
      item order between `row` and `region` items never matters. -/
      let regionFields := collectRegionFields (items.map (·.raw))
      let mut rowEventTerms : List (String × String × TSyntax `term) := []
      for item in items do
        if item.raw.getKind == ``leanrxItemRowEvent then
          rowEventTerms := rowEventTerms ++
            [← elabRowEventItem regionFields item.raw (← sourceSpanTerm item)]
        else if item.raw.getKind == ``leanrxItemRowTypedEvent then
          rowEventTerms := rowEventTerms ++
            [← elabRowTypedEventItem regionFields item.raw (← sourceSpanTerm item)]
      let mut values : Array (TSyntax `term) := #[]
      let mut events : Array (TSyntax `term) := #[]
      let mut typedEvents : Array (TSyntax `term) := #[]
      let mut declarations : Array (TSyntax `term) := #[]
      let mut childTerms : Array (TSyntax `term) := #[]
      let mut childNames : List String := []
      let mut regionTerms : Array (TSyntax `term) := #[]
      let mut filterTerms : Array (TSyntax `term) := #[]
      let mut propTerms : Array (TSyntax `term) := #[]
      let mut viewTerm? : Option (TSyntax `term) := none
      for item in items do
        let itemSpan ← sourceSpanTerm item
        match item with
        | `(leanrxComponentItem| $role:ident $itemName:ident
              ($param:ident : $ty:ident) := $rhs:term;) =>
            let roleName ← checkRole role
            unless roleName == "event" do
              throwErrorAt role
                s!"error[LRX-ELAB-003]: payload parameters are valid only on event items, not {roleName}"
            let nameLit := Syntax.mkStrLit itemName.getId.eraseMacroScopes.toString
            let paramLit := Syntax.mkStrLit param.getId.eraseMacroScopes.toString
            let assigned ← match rhs with
              | `($head:ident $field:ident $payload:ident) =>
                  if head.getId.eraseMacroScopes == `set &&
                      payload.getId.eraseMacroScopes == param.getId.eraseMacroScopes then
                    pure field
                  else
                    throwErrorAt rhs
                      "error[LRX-ELAB-108]: a typed event must assign its payload parameter with `set field param`"
              | _ =>
                  throwErrorAt rhs
                    "error[LRX-ELAB-108]: a typed event must assign its payload parameter with `set field param`"
            let wrapper ← match ty.getId.eraseMacroScopes.toString with
              | "String" => `(LeanRx.AnyTypedEvent.string)
              | "Bool" => `(LeanRx.AnyTypedEvent.bool)
              | other => throwErrorAt ty
                  s!"error[LRX-ELAB-109]: typed event payloads support String and Bool, not {other}"
            typedEvents := typedEvents.push (← `($wrapper (LeanRx.TypedEventSpec.assign
              $nameLit $paramLit $assigned $itemSpan : LeanRx.TypedEventSpec _ $ty)))
            declarations := declarations.push (← `(LeanRx.SurfaceDecl.mk
              LeanRx.SurfaceRole.event $nameLit $itemSpan))
        | `(leanrxComponentItem| $role:ident $itemName:ident : $ty:ident := $value:term;) =>
            let roleName ← checkRole role
            unless roleName == "state" do
              throwErrorAt role
                s!"error[LRX-ELAB-003]: literal type annotations are valid only on state items, not {roleName}"
            let literal ← scalarLiteralTerm ty value
            values := values.push (← `(LeanRx.ValueSpec.withSpan
              (LeanRx.ValueSpec.state $itemName $literal) $itemSpan))
            let nameLit := Syntax.mkStrLit itemName.getId.eraseMacroScopes.toString
            declarations := declarations.push (← `(LeanRx.SurfaceDecl.mk
              LeanRx.SurfaceRole.state $nameLit $itemSpan))
        | _ =>
          if item.raw.getKind == ``leanrxItemProp then
            propTerms := propTerms.push (← elabPropItem item.raw itemSpan)
          else if item.raw.getKind == ``leanrxItemRegion then
            regionTerms := regionTerms.push
              (← elabRegionItem item.raw itemSpan rowEventTerms)
          else if item.raw.getKind == ``leanrxItemRowEvent ||
              item.raw.getKind == ``leanrxItemRowTypedEvent then
            pure ()
          else if item.raw.getKind == ``leanrxItemFilter then
            filterTerms := filterTerms.push
              (← elabFilterItem regionFields item.raw itemSpan)
          else if item.raw.getKind == ``leanrxItemValue then
            let role : Ident := ⟨item.raw[0]⟩
            let itemName : Ident := ⟨item.raw[1]⟩
            let steps := (sepByElems item.raw[3]).map fun step => (⟨step⟩ : TSyntax `term)
            let roleName ← checkRole role
            let nameLit := Syntax.mkStrLit itemName.getId.eraseMacroScopes.toString
            match roleName with
            | "state" | "derived" =>
                unless steps.size == 1 do
                  throwErrorAt item
                    s!"error[LRX-ELAB-104]: {roleName} items take exactly one value"
                values := values.push (← `(LeanRx.ValueSpec.withSpan
                  (leanrx_component_value% $itemName $(steps[0]!)) $itemSpan))
                let surfaceRole ← if roleName == "state" then
                    `(LeanRx.SurfaceRole.state)
                  else `(LeanRx.SurfaceRole.derived)
                declarations := declarations.push (← `(LeanRx.SurfaceDecl.mk
                  $surfaceRole $nameLit $itemSpan))
            | "event" => do
                let mut stepTerms : Array (TSyntax `term) := #[]
                let mut passthrough? : Option (TSyntax `term) := none
                for step in steps do
                  match ← updateStepTerm? regionFields step with
                  | some update => stepTerms := stepTerms.push update
                  | none =>
                      if steps.size == 1 then
                        passthrough? := some step
                      else
                        throwErrorAt step
                          "error[LRX-ELAB-104]: event steps are `set field (expr)` or `dispatch event`"
                let eventTerm ← match passthrough? with
                  | some value => `(LeanRx.EventSpec.withSpan $value $itemSpan)
                  | none => do
                      let mut update := stepTerms[0]!
                      for step in stepTerms[1:] do
                        update ← `(LeanRx.Update.sequence $update $step)
                      `(LeanRx.EventSpec.mk $nameLit $update $itemSpan)
                events := events.push eventTerm
                declarations := declarations.push (← `(LeanRx.SurfaceDecl.mk
                  LeanRx.SurfaceRole.event $nameLit $itemSpan))
            | _ =>
                throwErrorAt role
                  "error[LRX-ELAB-003]: view items are written `view := …` without a name"
          else if item.raw.getKind == ``leanrxItemView then
            let role : Ident := ⟨item.raw[0]⟩
            let value : TSyntax `term := ⟨item.raw[2]⟩
            let roleName ← checkRole role
            unless roleName == "view" do
              throwErrorAt role
                s!"error[LRX-ELAB-003]: {roleName} items declare a name before `:=`"
            if viewTerm?.isSome then
              throwErrorAt item "error[LRX-ELAB-002]: component must have exactly one view"
            /- The child table mirrors the jsx lowering: an attr-less capitalized
            head becomes a `View.child` reference exactly when `{name}_spec` is
            in scope, so collect those heads into `ComponentSpec.children`. -/
            for tag in collectComponentHeads value.raw do
              if ← liftTermElabM (resolvesToComponentSpec tag) then
                let shortName := componentShortName tag
                unless childNames.contains shortName do
                  childNames := childNames ++ [shortName]
                  let tagLit := Syntax.mkStrLit shortName
                  childTerms := childTerms.push
                    (← `(LeanRx.ChildComponent.of $tagLit $(← sourceSpanTerm tag)))
            let counted ← rewriteCountRefs regionFields
              (rewritePropRefs declaredProps value.raw)
            let rewritten : TSyntax `term := ⟨rewriteEventRefs declaredEvents counted⟩
            viewTerm? := some (← `(LeanRx.View.withSpan $rewritten $itemSpan))
          else
            throwErrorAt item "error[LRX-ELAB-003]: malformed component item"
      let viewTerm ← viewTerm?.getDM <| throwErrorAt name
        "error[LRX-ELAB-001]: component requires a view declaration"
      let schemaName := mkIdent (name.getId.appendAfter "_schema")
      let specName := mkIdent (name.getId.appendAfter "_spec")
      let checkName := mkIdent (name.getId.appendAfter "_check")
      let declarationsName := mkIdent (name.getId.appendAfter "_declarations")
      let componentName : TSyntax `term := ⟨Syntax.mkStrLit name.getId.toString⟩
      let componentSpan ← sourceSpanTerm name
      elabCommand (← `(abbrev $schemaName : LeanRx.Schema := $schemaTerm))
      elabCommand (← `(def $declarationsName : List LeanRx.SurfaceDecl := [$declarations,*]))
      elabCommand (← `(abbrev $specName : LeanRx.ComponentSpec $schemaName := {
        name := $componentName
        values := #[$values,*]
        events := #[$events,*]
        typedEvents := #[$typedEvents,*]
        view := $viewTerm
        surface := #[$declarations,*]
        children := #[$childTerms,*]
        regions := #[$regionTerms,*]
        filters := #[$filterTerms,*]
        props := #[$propTerms,*]
        span := $componentSpan }))
      elabCommand (← `(abbrev $checkName := LeanRx.ComponentSpec.check $specName))
      let messageTerm ← `(term| LeanRx.ComponentSpec.validationMessage $specName)
      let message : String ← liftTermElabM do
        let expression ← Term.elabTermEnsuringType messageTerm (mkConst ``String)
        Term.synthesizeSyntheticMVarsNoPostponing
        let expression ← instantiateMVars expression
        /- This isolated compile-time evaluation reports the total public validator's
        exact structured message; generated unsafe wrappers are audited by name. -/
        unsafe Meta.evalExpr (checkMeta := false) String (mkConst ``String) expression
      unless message.isEmpty do
        throwErrorAt name message

end LeanRxDsl
