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
  atomic(ident ident "(" ident ":" ident ")" ":=") sepBy1(term, " then ") ";" : leanrxComponentItem
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
children of an inline view to the internal `regionCount%` child (ADR-0050),
`hidden={count region == 0}` attributes to the internal
`regionHidden% "region"` attribute (ADR-0058), and
`checked={count region == 0}` attributes to the internal
`regionChecked% "region"` attribute (ADR-0060). The `count` head with an
argument is claimed by the rewrite — unnamed dynamic text is rejected
downstream either way, so the shape cannot collide with a legitimate child —
and region names resolve against the declared inventory here, where the
inventory exists. A `hidden` attribute with any other dynamic value is the
sealed surface's rejection: the visibility subject is one declared region's
total row count against the zero literal — predicate counts, other
comparison operators, threshold literals, negation, composition, and
general aggregate expressions are not visibility subjects. A `checked`
attribute claims only count-headed values — the same two sealed shapes
against the same zero literal — because every other dynamic `checked`
value keeps its meaning: the ADR-0038 controlled reflection at component
scope and the ADR-0049 row checked reflection in row templates. -/
private partial def rewriteCountRefs (regionFields : List (String × List String))
    (stx : Syntax) : CommandElabM Syntax := do
  let resolve (region : TSyntax `ident) : CommandElabM (List String) := do
    let name := region.getId.eraseMacroScopes.toString
    match regionFields.find? (·.1 == name) with
    | some entry => pure entry.2
    | none =>
        throwErrorAt region
          s!"error[LRX-ELAB-119]: count references unknown region {name}"
  let countChild? (value : TSyntax `term) :
      CommandElabM (Option (TSyntax `leanrxJsxChild)) := do
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
  /- The sealed empty-region visibility attribute (ADR-0058/0059): exactly
  `hidden={count region == 0}` or
  `hidden={count region (field == "literal") == 0}` over a declared region
  rewrites; every other dynamic `hidden` value reports the sealed surface. -/
  let hiddenAttr (info : SourceInfo) (value : TSyntax `term) :
      CommandElabM Syntax := do
    let accept (region : TSyntax `ident)
        (predicate? : Option (TSyntax `ident × TSyntax `str)) :
        CommandElabM Syntax := do
      let fields ← resolve region
      let ref := region.raw.getHeadInfo
      let head := #[Syntax.atom ref "regionHidden%",
        Syntax.mkStrLit region.getId.eraseMacroScopes.toString (info := ref)]
      let tail ← match predicate? with
        | none => pure #[mkNullNode]
        | some (field, lit) => do
            let fieldName := field.getId.eraseMacroScopes.toString
            let index ← match fields.idxOf? fieldName with
              | some index => pure index
              | none =>
                  throwErrorAt field
                    s!"error[LRX-ELAB-119]: unknown row field {fieldName}; declared fields are {renderFields fields}"
            pure #[mkNullNode
              #[Syntax.mkNumLit (toString index) (info := ref), lit.raw]]
      pure (.node info ``LeanRxDsl.leanrxJsxAttrRegionHidden (head ++ tail))
    let requireZero (lit : TSyntax `num) : CommandElabM Unit := do
      unless lit.getNat == 0 do
        throwErrorAt lit
          "error[LRX-ELAB-125]: a hidden reflection compares its row count against the zero literal only (ADR-0058/0059)"
    match value with
    | `($head:ident $region:ident == $lit:num) =>
        if head.getId.eraseMacroScopes == `count then do
          requireZero lit
          accept region none
        else
          throwErrorAt value
            "error[LRX-ELAB-125]: a hidden reflection is written hidden=\{count region == 0} or hidden=\{count region (field == \"literal\") == 0} (ADR-0058/0059)"
    | `($head:ident $region:ident ($field:ident == $strLit:str) == $lit:num) =>
        if head.getId.eraseMacroScopes == `count then do
          requireZero lit
          accept region (some (field, strLit))
        else
          throwErrorAt value
            "error[LRX-ELAB-125]: a hidden reflection is written hidden=\{count region == 0} or hidden=\{count region (field == \"literal\") == 0} (ADR-0058/0059)"
    | _ =>
        throwErrorAt value
          "error[LRX-ELAB-125]: a hidden reflection is written hidden=\{count region == 0} or hidden=\{count region (field == \"literal\") == 0}: one declared region's total or predicate row count against the zero literal (ADR-0058/0059)"
  /- The sealed toggle-all checked attribute (ADR-0060): exactly
  `checked={count region == 0}` or
  `checked={count region (field == "literal") == 0}` over a declared region
  rewrites; a count-headed value in any other shape reports the sealed
  surface, and every non-count value falls through untouched — it keeps the
  ADR-0038 controlled reflection meaning at component scope and the
  ADR-0049 row checked reflection in row templates. -/
  let checkedAttr? (info : SourceInfo) (value : TSyntax `term) :
      CommandElabM (Option Syntax) := do
    let accept (region : TSyntax `ident)
        (predicate? : Option (TSyntax `ident × TSyntax `str)) :
        CommandElabM Syntax := do
      let fields ← resolve region
      let ref := region.raw.getHeadInfo
      let head := #[Syntax.atom ref "regionChecked%",
        Syntax.mkStrLit region.getId.eraseMacroScopes.toString (info := ref)]
      let tail ← match predicate? with
        | none => pure #[mkNullNode]
        | some (field, lit) => do
            let fieldName := field.getId.eraseMacroScopes.toString
            let index ← match fields.idxOf? fieldName with
              | some index => pure index
              | none =>
                  throwErrorAt field
                    s!"error[LRX-ELAB-119]: unknown row field {fieldName}; declared fields are {renderFields fields}"
            pure #[mkNullNode
              #[Syntax.mkNumLit (toString index) (info := ref), lit.raw]]
      pure (.node info ``LeanRxDsl.leanrxJsxAttrRegionChecked (head ++ tail))
    let requireZero (lit : TSyntax `num) : CommandElabM Unit := do
      unless lit.getNat == 0 do
        throwErrorAt lit
          "error[LRX-ELAB-125]: a checked reflection compares its row count against the zero literal only (ADR-0060)"
    match value with
    | `($head:ident $region:ident == $lit:num) =>
        if head.getId.eraseMacroScopes == `count then do
          requireZero lit
          pure (some (← accept region none))
        else pure none
    | `($head:ident $region:ident ($field:ident == $strLit:str) == $lit:num) =>
        if head.getId.eraseMacroScopes == `count then do
          requireZero lit
          pure (some (← accept region (some (field, strLit))))
        else pure none
    | `($head:ident $_region:ident) =>
        if head.getId.eraseMacroScopes == `count then
          throwErrorAt value
            "error[LRX-ELAB-125]: a checked reflection is written checked=\{count region == 0} or checked=\{count region (field == \"literal\") == 0}: one declared region's total or predicate row count against the zero literal (ADR-0060)"
        else pure none
    | `($head:ident $_region:ident ($_:ident == $_:str)) =>
        if head.getId.eraseMacroScopes == `count then
          throwErrorAt value
            "error[LRX-ELAB-125]: a checked reflection is written checked=\{count region == 0} or checked=\{count region (field == \"literal\") == 0}: one declared region's total or predicate row count against the zero literal (ADR-0060)"
        else pure none
    | _ => pure none
  match stx with
  | .node info kind args =>
      if kind == ``LeanRxDsl.leanrxJsxChildDynamic && args.size == 3 then
        match ← countChild? ⟨args[1]!⟩ with
        | some child => pure child.raw
        | none => pure (.node info kind (← args.mapM (rewriteCountRefs regionFields)))
      else if kind == ``LeanRxDsl.leanrxJsxAttrDynamic && args.size == 5 &&
          args[0]!.isIdent && args[0]!.getId.eraseMacroScopes == `hidden then
        hiddenAttr info ⟨args[3]!⟩
      else if kind == ``LeanRxDsl.leanrxJsxAttrDynamic && args.size == 5 &&
          args[0]!.isIdent && args[0]!.getId.eraseMacroScopes == `checked then
        match ← checkedAttr? info ⟨args[3]!⟩ with
        | some attr => pure attr
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
literals, `++` concatenation, and the ADR-0054 `trim` unary — nothing else
enters row scope. Inside a typed row event right-hand side (ADR-0046),
`payload?` names the declared payload parameter, which lowers to
`RowExpr.payload`. -/
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
  | `($head:ident $arg:term) =>
      /- The sealed trim unary (ADR-0054): `trim field` or `trim (expr)` —
      the one string normalization in row scope, not a general function
      vocabulary. -/
      if head.getId.eraseMacroScopes == `trim then do
        let innerTerm ← rowExprTerm fields payload? arg
        `(LeanRx.RowExpr.trim $innerTerm)
      else
        throwErrorAt value
          "error[LRX-ELAB-115]: row expressions are row fields, string literals, ++, and trim"
  | _ =>
      throwErrorAt value
        "error[LRX-ELAB-115]: row expressions are row fields, string literals, ++, and trim"

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

/-- Whether one row event step is an ADR-0052 `when "key" (…)` arm. -/
private def rowKeyArm? (step : TSyntax `term) :
    Option (TSyntax `str × TSyntax `term) :=
  match step with
  | `($head:ident $lit:str $body:term) =>
      if head.getId.eraseMacroScopes == `when then some (lit, body) else none
  | _ => none

/-- Whether one row event step is an ADR-0053 guarded stage — an
`if … then … else …` term at step position. The pieces are validated by
`rowGuardedStageTerm`, so a malformed guard reports its own repair instead of
the generic step message. -/
private def rowGuardStep? (step : TSyntax `term) :
    Option (TSyntax `term × TSyntax `term × TSyntax `term) :=
  match step with
  | `(if $cond:term then $thenBranch:term else $elseBranch:term) =>
      some (cond, thenBranch, elseBranch)
  | _ => none

/-- Lower one guarded row stage (ADR-0053):
`if field == "literal" then remove else (set field (expr), …)`. The guard is
one row-field equality against one string literal — the subject may sit
behind the ADR-0054 trim unary, `if trim field == "literal" then …` — the
guard hit is the sealed `remove` and nothing else, and the else-steps carry
the ADR-0043 update shape — the arm-body spelling, since a guarded stage
stands alone. -/
private def rowGuardedStageTerm (fields : List String)
    (cond thenBranch elseBranch : TSyntax `term) :
    CommandElabM (TSyntax `term) := do
  let (subject, guardLit) ← match cond with
    | `($lhs:term == $lit:str) => pure (lhs, lit)
    | _ =>
        throwErrorAt cond
          "error[LRX-ELAB-122]: a row guard is written `if field == \"literal\" then remove else (set field (expr), …)` (ADR-0053)"
  let (guardField, trimmed) ← match subject with
    | `($field:ident) => pure (field, false)
    | `($head:ident $arg:term) =>
        if head.getId.eraseMacroScopes == `trim then
          match arg with
          | `($field:ident) => pure (field, true)
          | `(($field:ident)) => pure (field, true)
          | _ =>
              throwErrorAt subject
                "error[LRX-ELAB-122]: a row guard subject is one row field, optionally trimmed — `if trim field == \"literal\" then remove else (…)` (ADR-0054)"
        else
          throwErrorAt subject
            "error[LRX-ELAB-122]: a row guard subject is one row field, optionally trimmed — `if trim field == \"literal\" then remove else (…)` (ADR-0054)"
    | _ =>
        throwErrorAt subject
          "error[LRX-ELAB-122]: a row guard subject is one row field, optionally trimmed — `if trim field == \"literal\" then remove else (…)` (ADR-0054)"
  let isRemove := match thenBranch with
    | `($head:ident) => head.getId.eraseMacroScopes == `remove
    | _ => false
  unless isRemove do
    throwErrorAt thenBranch
      "error[LRX-ELAB-122]: the guard hit of a guarded row event is the sealed `remove` — assignments go in the else-steps"
  let fieldName := guardField.getId.eraseMacroScopes.toString
  let index ← match fields.idxOf? fieldName with
    | some index => pure index
    | none =>
        throwErrorAt guardField
          s!"error[LRX-ELAB-122]: unknown row field {fieldName}; declared fields are {renderFields fields}"
  let steps ← match elseBranch with
    | `(($first:term, $rest:term,*)) => pure (#[first] ++ rest.getElems)
    | `(($inner:term)) => pure #[inner]
    | _ =>
        throwErrorAt elseBranch
          "error[LRX-ELAB-122]: the else-steps of a guarded row event are written `(set field (expr), …)`"
  let assignments ← rowUpdateAssignments fields none steps
  let indexLit := Syntax.mkNumLit (toString index)
  let subjectTerm ← if trimmed then
      `(LeanRx.RowExpr.trim (LeanRx.RowExpr.field $indexLit))
    else
      `(LeanRx.RowExpr.field $indexLit)
  `(LeanRx.RowStage.mk [$assignments,*] (some (LeanRx.RowGuard.mk $subjectTerm $guardLit)))

/-- Lower one guarded component event (ADR-0055):
`if draft == "" then skip else (set field (expr), …)`. The guard subject is
one `String` state field, raw or behind the one trim unary; the compared
literal is the empty string and nothing else; the guard hit is the sealed
`skip` — the whole event is a no-op before the transaction begins — and the
else-steps carry the ordinary component event steps in the arm-body
spelling, since a guarded event stands alone. -/
private def guardedStepsTerm (regionFields : List (String × List String))
    (itemSpan : TSyntax `term)
    (cond thenBranch elseBranch : TSyntax `term) :
    CommandElabM (TSyntax `term × TSyntax `term) := do
  let (subject, guardLit) ← match cond with
    | `($lhs:term == $lit:str) => pure (lhs, lit)
    | _ =>
        throwErrorAt cond
          "error[LRX-ELAB-123]: a skip guard is written `if draft == \"\" then skip else (set field (expr), …)` (ADR-0055)"
  let (guardField, trimmed) ← match subject with
    | `($field:ident) => pure (field, false)
    | `($head:ident $arg:term) =>
        if head.getId.eraseMacroScopes == `trim then
          match arg with
          | `($field:ident) => pure (field, true)
          | `(($field:ident)) => pure (field, true)
          | _ =>
              throwErrorAt subject
                "error[LRX-ELAB-123]: a skip guard subject is one String state field, optionally trimmed — `if trim draft == \"\" then skip else (…)` (ADR-0055)"
        else
          throwErrorAt subject
            "error[LRX-ELAB-123]: a skip guard subject is one String state field, optionally trimmed — `if trim draft == \"\" then skip else (…)` (ADR-0055)"
    | _ =>
        throwErrorAt subject
          "error[LRX-ELAB-123]: a skip guard subject is one String state field, optionally trimmed — `if trim draft == \"\" then skip else (…)` (ADR-0055)"
  unless guardLit.getString == "" do
    throwErrorAt guardLit
      "error[LRX-ELAB-123]: a skip guard compares against the empty literal only — the guard is TodoMVC's add contract, not a conditional event vocabulary (ADR-0055)"
  let isSkip := match thenBranch with
    | `($head:ident) => head.getId.eraseMacroScopes == `skip
    | _ => false
  unless isSkip do
    throwErrorAt thenBranch
      "error[LRX-ELAB-123]: the guard hit of a guarded event is the sealed `skip` — steps go in the else-steps (ADR-0055)"
  let stepsStx ← match elseBranch with
    | `(($first:term, $rest:term,*)) => pure (#[first] ++ rest.getElems)
    | `(($inner:term)) => pure #[inner]
    | _ =>
        throwErrorAt elseBranch
          "error[LRX-ELAB-123]: the else-steps of a guarded event are written `(set field (expr), …)` (ADR-0055)"
  let mut stepTerms : Array (TSyntax `term) := #[]
  for step in stepsStx do
    match ← updateStepTerm? regionFields step with
    | some update => stepTerms := stepTerms.push update
    | none =>
        throwErrorAt step
          "error[LRX-ELAB-123]: the else-steps of a guarded event are `set field (expr)`, `dispatch event`, or the sealed region steps (ADR-0055)"
  let mut update := stepTerms[0]!
  for step in stepTerms[1:] do
    update ← `(LeanRx.Update.sequence $update $step)
  let trimmedTerm ← if trimmed then `(Bool.true) else `(Bool.false)
  pure (← `(LeanRx.EventGuard.mk $guardField $trimmedTerm $itemSpan), update)

private def guardedEventTerm (regionFields : List (String × List String))
    (nameLit itemSpan : TSyntax `term)
    (cond thenBranch elseBranch : TSyntax `term) : CommandElabM (TSyntax `term) := do
  let (guard, update) ← guardedStepsTerm regionFields itemSpan cond thenBranch elseBranch
  `(LeanRx.EventSpec.mk $nameLit $update $itemSpan (some $guard))

/-- Whether a syntax tree references `name` as an identifier. The sealed
discriminant of a key-branched component event is not spellable inside an
arm (ADR-0056, mirroring the ADR-0052 row rejection): the matched literal
already fixes it, and the component update language has no payload
vocabulary to receive it. -/
private partial def referencesName (name : Lean.Name) : Syntax → Bool
  | .ident _ _ value _ => value.eraseMacroScopes == name
  | .node _ _ args => args.any (referencesName name)
  | _ => false

/-- Fold ordinary component event steps into one `Update` term — the
arm-body/else-steps spelling shared by the ADR-0055 guard miss and the
ADR-0056 key arms. -/
private def componentStepsUpdate (regionFields : List (String × List String))
    (repair : String) (steps : Array (TSyntax `term)) :
    CommandElabM (TSyntax `term) := do
  let mut stepTerms : Array (TSyntax `term) := #[]
  for step in steps do
    match ← updateStepTerm? regionFields step with
    | some update => stepTerms := stepTerms.push update
    | none => throwErrorAt step repair
  let mut update := stepTerms[0]!
  for step in stepTerms[1:] do
    update ← `(LeanRx.Update.sequence $update $step)
  pure update

/-- Lower one arm body of a key-branched component event (ADR-0056): a tuple
of ordinary component event steps, or one ADR-0055 skip-guarded sequence —
`when "Enter" (if trim draft == "" then skip else (…))`. -/
private def componentKeyArm (regionFields : List (String × List String))
    (itemSpan : TSyntax `term) (keyLit : TSyntax `str) (body : TSyntax `term) :
    CommandElabM (TSyntax `term) := do
  let stepsRepair :=
    "error[LRX-ELAB-124]: a key arm's steps are `set field (expr)`, `dispatch event`, or the sealed region steps (ADR-0056)"
  match body with
  | `(($first:term, $rest:term,*)) =>
      let update ← componentStepsUpdate regionFields stepsRepair
        (#[first] ++ rest.getElems)
      `(LeanRx.KeyEventArm.mk $keyLit $update $itemSpan none)
  | `(($inner:term)) =>
      match rowGuardStep? inner with
      | some (cond, thenBranch, elseBranch) =>
          let (guard, update) ← guardedStepsTerm regionFields itemSpan
            cond thenBranch elseBranch
          `(LeanRx.KeyEventArm.mk $keyLit $update $itemSpan (some $guard))
      | none =>
          let update ← componentStepsUpdate regionFields stepsRepair #[inner]
          `(LeanRx.KeyEventArm.mk $keyLit $update $itemSpan none)
  | _ =>
      throwErrorAt body
        "error[LRX-ELAB-124]: a key arm is written `when \"Enter\" (set field (expr), …)` (ADR-0056)"

/-- Lower the arm table of one key-branched component event (ADR-0056):
every step must be a `when "key" (…)` arm, and the declared discriminant is
not spellable inside an arm body. -/
private def componentKeyArms (regionFields : List (String × List String))
    (paramName : Lean.Name) (itemSpan : TSyntax `term)
    (steps : Array (TSyntax `term)) : CommandElabM (Array (TSyntax `term)) := do
  let mut arms : Array (TSyntax `term) := #[]
  for step in steps do
    match rowKeyArm? step with
    | some (keyLit, body) =>
        if referencesName paramName body.raw then
          throwErrorAt body
            "error[LRX-ELAB-124]: a key-branched event references the payload in an arm; the key literal already fixes it (ADR-0056)"
        arms := arms.push (← componentKeyArm regionFields itemSpan keyLit body)
    | none =>
        throwErrorAt step
          "error[LRX-ELAB-124]: a key-branched event mixes no other steps with its `when` arms (ADR-0056)"
  pure arms

/-- Lower the arm table of one key-branched row event (ADR-0052): every step
must be a `when "key" (set field (expr), …)` arm whose inner steps carry the
ADR-0043 update shape with payload references rejected — the key literal
already fixes the discriminant. An arm body may instead be one ADR-0053
guarded stage, `when "Enter" (if field == "literal" then remove else (…))`. -/
private def rowKeySelectArms (fields : List String)
    (steps : Array (TSyntax `term)) : CommandElabM (Array (TSyntax `term)) := do
  let mut arms : Array (TSyntax `term) := #[]
  for step in steps do
    match rowKeyArm? step with
    | some (keyLit, body) =>
        let stage ← match body with
          | `(($first:term, $rest:term,*)) => do
              let assignments ← rowUpdateAssignments fields none (#[first] ++ rest.getElems)
              `(LeanRx.RowStage.mk [$assignments,*] none)
          | `(($inner:term)) =>
              match rowGuardStep? inner with
              | some (cond, thenBranch, elseBranch) =>
                  rowGuardedStageTerm fields cond thenBranch elseBranch
              | none => do
                  let assignments ← rowUpdateAssignments fields none #[inner]
                  `(LeanRx.RowStage.mk [$assignments,*] none)
          | _ =>
              throwErrorAt body
                "error[LRX-ELAB-121]: a key arm is written `when \"Enter\" (set field (expr), …)`"
        arms := arms.push (← `(($keyLit, $stage)))
    | none =>
        throwErrorAt step
          "error[LRX-ELAB-121]: a key-branched row event mixes no other steps with its `when` arms"
  pure arms

/-- Elaborate one `row region event := set field (expr) then …;` item to its
region name, event name, and sealed `RowEventSpec` (ADR-0043). -/
private def elabRowEventItem (regionFields : List (String × List String))
    (item : Syntax) (itemSpan : TSyntax `term) :
    CommandElabM (String × String × TSyntax `term) := do
  let eventName : Ident := ⟨item[2]⟩
  let (region, fields) ← rowEventContext regionFields ⟨item[0]⟩ ⟨item[1]⟩ eventName
  let steps := (sepByElems item[4]).map fun step => (⟨step⟩ : TSyntax `term)
  for step in steps do
    if (rowKeyArm? step).isSome then
      throwErrorAt step
        "error[LRX-ELAB-121]: a key-branched row event declares a String payload parameter — `row region event (pressed : String) := when \"Enter\" (…)` (ADR-0052)"
  let nameLit := Syntax.mkStrLit eventName.getId.eraseMacroScopes.toString
  /- An `if … then … else …` step is the ADR-0053 guarded stage; it stands
  alone — a guarded row event selects between remove and one commit stage,
  never a step sequence. -/
  if steps.any fun step => (rowGuardStep? step).isSome then
    unless steps.size == 1 do
      throwErrorAt item
        "error[LRX-ELAB-122]: a guarded row event mixes no other steps with its guard (ADR-0053)"
    let some (cond, thenBranch, elseBranch) := rowGuardStep? steps[0]! |
      throwErrorAt item "error[LRX-ELAB-122]: a guarded row event lost its guard step"
    let stage ← rowGuardedStageTerm fields cond thenBranch elseBranch
    pure (region, eventName.getId.eraseMacroScopes.toString,
      ← `(LeanRx.RowEventSpec.mk $nameLit (LeanRx.RowAction.update $stage)
          false $itemSpan))
  else
  let assignments ← rowUpdateAssignments fields none steps
  pure (region, eventName.getId.eraseMacroScopes.toString,
    ← `(LeanRx.RowEventSpec.mk $nameLit
        (LeanRx.RowAction.update (LeanRx.RowStage.mk [$assignments,*] none))
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
  let nameLit := Syntax.mkStrLit eventName.getId.eraseMacroScopes.toString
  /- A typed row event whose steps are `when "key" (…)` arms is the ADR-0052
  key-branched selection: the declared parameter is the discriminant, named
  in the head and compared implicitly by each arm — the ADR-0051 filter-table
  shape in row scope. -/
  if steps.any fun step => (rowKeyArm? step).isSome then
    let arms ← rowKeySelectArms fields steps
    pure (region, eventName.getId.eraseMacroScopes.toString,
      ← `(LeanRx.RowEventSpec.mk $nameLit (LeanRx.RowAction.keySelect [$arms,*])
          true $itemSpan))
  else
  /- A guarded stage in a typed row event (ADR-0053) is rejected here with
  its own repair: guards select commit paths, and a payload-taking event
  fires per keystroke — outside a `when` key arm the shapes never mix. -/
  for step in steps do
    if (rowGuardStep? step).isSome then
      throwErrorAt step
        "error[LRX-ELAB-122]: a guarded row event takes no payload parameter — guards live on payload-less row events and `when` key arms (ADR-0053)"
  let assignments ← rowUpdateAssignments fields (some paramName) steps
  pure (region, eventName.getId.eraseMacroScopes.toString,
    ← `(LeanRx.RowEventSpec.mk $nameLit
        (LeanRx.RowAction.update (LeanRx.RowStage.mk [$assignments,*] none))
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
        if item.raw.getKind == ``leanrxItemTypedEvent then
          let role : Ident := ⟨item.raw[0]⟩
          if roleName role == "event" then
            let itemName : Ident := ⟨item.raw[1]⟩
            declaredEvents := declaredEvents ++ [itemName.getId.eraseMacroScopes.toString]
        else if item.raw.getKind == ``leanrxItemProp then
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
      let mut keyEventTerms : Array (TSyntax `term) := #[]
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
          if item.raw.getKind == ``leanrxItemTypedEvent then
            let role : Ident := ⟨item.raw[0]⟩
            let itemName : Ident := ⟨item.raw[1]⟩
            let param : Ident := ⟨item.raw[3]⟩
            let ty : Ident := ⟨item.raw[5]⟩
            let roleName ← checkRole role
            unless roleName == "event" do
              throwErrorAt role
                s!"error[LRX-ELAB-003]: payload parameters are valid only on event items, not {roleName}"
            let steps := (sepByElems item.raw[8]).map fun step => (⟨step⟩ : TSyntax `term)
            let nameLit := Syntax.mkStrLit itemName.getId.eraseMacroScopes.toString
            let paramLit := Syntax.mkStrLit param.getId.eraseMacroScopes.toString
            /- A payload-taking event whose steps are `when "key" (…)` arms is
            the ADR-0056 key-branched component event: the ADR-0052 selection
            lifted to component scope, each arm body an ordinary component
            step sequence optionally behind the ADR-0055 skip guard. -/
            if steps.any fun step => (rowKeyArm? step).isSome then
              unless ty.getId.eraseMacroScopes.toString == "String" do
                throwErrorAt ty
                  s!"error[LRX-ELAB-124]: a key-branched event declares a String payload parameter, not {ty.getId.eraseMacroScopes} (ADR-0056)"
              let arms ← componentKeyArms regionFields
                param.getId.eraseMacroScopes itemSpan steps
              keyEventTerms := keyEventTerms.push (← `(LeanRx.KeyEventSpec.mk
                $nameLit $paramLit [$arms,*] $itemSpan))
              declarations := declarations.push (← `(LeanRx.SurfaceDecl.mk
                LeanRx.SurfaceRole.event $nameLit $itemSpan))
            else
            let rhs ← match steps with
              | #[single] => pure single
              | _ =>
                  throwErrorAt item
                    "error[LRX-ELAB-108]: a typed event must assign its payload parameter with `set field param`"
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
          else if item.raw.getKind == ``leanrxItemProp then
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
                /- An `if … then … else …` step is the ADR-0055 skip guard;
                it stands alone — a guarded event pairs the sealed no-op hit
                with one else-step sequence, never further steps. -/
                if steps.any (fun step => (rowGuardStep? step).isSome) then
                  unless steps.size == 1 do
                    throwErrorAt item
                      "error[LRX-ELAB-123]: a guarded event mixes no other steps with its guard (ADR-0055)"
                  let some (cond, thenBranch, elseBranch) := rowGuardStep? steps[0]! |
                    throwErrorAt item
                      "error[LRX-ELAB-123]: a guarded event lost its guard step"
                  events := events.push (← guardedEventTerm regionFields nameLit
                    itemSpan cond thenBranch elseBranch)
                  declarations := declarations.push (← `(LeanRx.SurfaceDecl.mk
                    LeanRx.SurfaceRole.event $nameLit $itemSpan))
                else
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
                        `(LeanRx.EventSpec.mk $nameLit $update $itemSpan none)
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
        keyEvents := #[$keyEventTerms,*]
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
