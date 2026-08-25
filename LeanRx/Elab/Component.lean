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
  unless ["state", "derived", "event", "view", "region", "prop"].contains name do
    throwErrorAt role
      s!"error[LRX-ELAB-003]: unknown component item role {name}; expected state, derived, event, region, prop, or view"
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

/-- Interpret one sugared event step (`set field (expr)`, `dispatch event`, or
`append region (expr, …)`) as its explicit `Update` constructor; any other
shape is not a step. -/
private def updateStepTerm? (step : TSyntax `term) :
    CommandElabM (Option (TSyntax `term)) := do
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
      else pure none
  | `($head:ident $target:ident) =>
      if head.getId.eraseMacroScopes == `dispatch then
        let targetLit := Syntax.mkStrLit target.getId.eraseMacroScopes.toString
        pure (some (← `(LeanRx.Update.dispatch $targetLit)))
      else pure none
  | _ => pure none

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

private def rowAttrTerm (attr : Syntax) : CommandElabM (TSyntax `term) := do
  let attrStx : TSyntax `leanrxJsxAttr := ⟨attr⟩
  match attrStx with
  | `(leanrxJsxAttr| $_:ident = { $_:term }) =>
      throwErrorAt attr
        "error[LRX-ELAB-114]: row templates support static attributes and row event references only"
  | `(leanrxJsxAttr| class = { $_:term }) | `(leanrxJsxAttr| type = { $_:term }) =>
      throwErrorAt attr
        "error[LRX-ELAB-114]: row templates support static attributes and row event references only"
  | _ => `(leanrx_jsx_attr% $attrStx)

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
        unless value.raw.isIdent do
          throwErrorAt child
            "error[LRX-ELAB-114]: row templates project declared row fields by bare name"
        match fields.idxOf? (value.raw.getId.eraseMacroScopes.toString) with
        | some index =>
            let indexLit := Syntax.mkNumLit (toString index)
            `(LeanRx.RowNode.fieldText $indexLit $span)
        | none =>
            throwErrorAt child
              s!"error[LRX-ELAB-114]: unknown row field {value.raw.getId.eraseMacroScopes}; declared fields are {String.intercalate ", " fields}"
    | `(leanrxJsxChild| { $_:str : $_:term }) =>
        throwErrorAt child
          "error[LRX-ELAB-114]: named text sinks are not available inside row templates"
    | `(leanrxJsxChild| $element:leanrxJsxElement) => lowerRowElement fields element
    | _ =>
        throwErrorAt child
          "error[LRX-ELAB-114]: malformed row template child"

  private partial def lowerRowElement (fields : List String)
      (element : TSyntax `leanrxJsxElement) : CommandElabM (TSyntax `term) := do
    match element with
    | `(leanrxJsxElement| <$tag:ident $attrs:leanrxJsxAttr* >
          [$children:leanrxJsxChild,*]) => do
        let attrTerms ← attrs.mapM rowAttrTerm
        let childTerms ← children.getElems.mapM (lowerRowChild fields ·)
        let span ← sourceSpanTerm element
        `(LeanRx.RowNode.nodeWith (leanrx_jsx_tag% $tag) [$childTerms,*]
          (attrs := [$attrTerms,*]) (span := $span))
    | `(leanrxJsxElement| <$tag:ident $attrs:leanrxJsxAttr* />) => do
        let attrTerms ← attrs.mapM rowAttrTerm
        let span ← sourceSpanTerm element
        `(LeanRx.RowNode.nodeWith (leanrx_jsx_tag% $tag) []
          (attrs := [$attrTerms,*]) (span := $span))
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

/-- Elaborate one `region name (fields) := jsx% …;` item to its `RegionSpec`
(ADR-0041). The sealed row event vocabulary means every region declares exactly
the `remove` row event; templates opt in by binding `onClick={remove}`. -/
private def elabRegionItem (item : Syntax) (itemSpan : TSyntax `term) :
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
  let nameLit := Syntax.mkStrLit itemName.getId.eraseMacroScopes.toString
  let template ← match rhs with
    | `(jsx% $element:leanrxJsxElement) =>
        let rewritten : TSyntax `leanrxJsxElement :=
          ⟨rewriteEventRefs ["remove"] element.raw⟩
        lowerRowElement fieldNames.toList rewritten
    | _ =>
        throwErrorAt rhs
          "error[LRX-ELAB-111]: a region item takes an inline jsx% row template"
  let fieldLits : Array (TSyntax `term) :=
    fieldNames.map fun fieldName => ⟨Syntax.mkStrLit fieldName⟩
  `(LeanRx.RegionSpec.mk $nameLit #[$fieldLits,*] $template
    #[LeanRx.RowEventSpec.mk "remove" LeanRx.RowAction.remove $itemSpan] $itemSpan)

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

/- The single command elaborator now dispatches eight item kinds; compiling
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
      let mut values : Array (TSyntax `term) := #[]
      let mut events : Array (TSyntax `term) := #[]
      let mut typedEvents : Array (TSyntax `term) := #[]
      let mut declarations : Array (TSyntax `term) := #[]
      let mut childTerms : Array (TSyntax `term) := #[]
      let mut childNames : List String := []
      let mut regionTerms : Array (TSyntax `term) := #[]
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
            regionTerms := regionTerms.push (← elabRegionItem item.raw itemSpan)
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
                  match ← updateStepTerm? step with
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
            let rewritten : TSyntax `term :=
              ⟨rewriteEventRefs declaredEvents (rewritePropRefs declaredProps value.raw)⟩
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
