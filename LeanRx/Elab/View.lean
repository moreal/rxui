import LeanRx.View.Model
import LeanRx.Region.Keyed
import LeanRx.Component.Model
import LeanRx.Component.Dependent
import Lean.Elab.Macro
import Lean.Elab.Term
import Lean.Elab.SyntheticMVars
import Lean.Meta.Eval

open Lean Elab Macro Term Meta

/-! The scoped JSX-like surface.

One shared grammar lowers into two closed targets selected by the expected
type: the schema-typed safe `View` consumed by the generic component backend,
and the reference-only `Region.LogicalNode`/`KeyedItem` logical model used by
dynamic-region applications and differential tests. Keyed list syntax lowers
onto the existing keyed region IR, and a capitalized element nests another
component as an ordinary typed Lean application; a prop whose expected type is
`ImmutableProp` is wrapped through `ImmutableProp.of` with its attribute name.
Both targets keep closed tag/attribute whitelists with stable `LRX-VIEW-*`
diagnostics at the offending source ranges. -/

namespace LeanRxDsl

private def normalizedFileName : TermElabM String := do
  let fileName ← getFileName
  let currentDir ← IO.currentDir
  let rootPrefix := currentDir.toString ++ "/"
  pure <| if fileName.startsWith rootPrefix then
    (fileName.drop rootPrefix.length).toString
  else fileName

private def sourceSpanTerm (stx : Syntax) : TermElabM (TSyntax `term) := do
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

syntax "leanrx_source_span% " str : term

elab "leanrx_source_span% " marker:str : term => do
  let term ← sourceSpanTerm marker
  Term.elabTerm term (some (mkConst ``LeanRx.SourceSpan))

private def spanMarker (stx : Syntax) : TSyntax `str :=
  let start := stx.getPos?.getD 0
  let stop := stx.getTailPos?.getD start
  ⟨Syntax.mkStrLit "" (info := .synthetic start stop true)⟩

private def spanSyntax (stx : Syntax) : MacroM (TSyntax `term) := do
  let marker := spanMarker stx
  `(leanrx_source_span% $marker)

/- Attribute names parse as plain identifiers wherever Lean allows it, so the
DSL reserves no attribute tokens; `class` and `type` are Lean keywords and keep
explicit atoms. Name dispatch happens during lowering with the same closed
whitelist and diagnostics. -/
declare_syntax_cat leanrxJsxAttr
scoped syntax "class" "=" str : leanrxJsxAttr
scoped syntax "type" "=" str : leanrxJsxAttr
scoped syntax (name := leanrxJsxAttrNamed) ident "=" str : leanrxJsxAttr
scoped syntax "class" "=" "{" term "}" : leanrxJsxAttr
scoped syntax "type" "=" "{" term "}" : leanrxJsxAttr
scoped syntax (name := leanrxJsxAttrDynamic) ident "=" "{" term "}" : leanrxJsxAttr
/- A bare identifier attribute is the sealed marker shape; only the row
templates' `autoFocus` marker inhabits it today (ADR-0048). -/
scoped syntax (name := leanrxJsxAttrMarker) ident : leanrxJsxAttr
/- Internal target of the component command's sealed empty-region visibility
rewrite (ADR-0058/0059); `hidden={count region == 0}` attributes become
`regionHidden% "region"` and `hidden={count region (field == "literal") == 0}`
attributes become `regionHidden% "region" fieldIndex "literal"` before
lowering. -/
scoped syntax (name := leanrxJsxAttrRegionHidden)
  "regionHidden%" str (num str)? : leanrxJsxAttr
/- Internal target of the component command's sealed toggle-all checked
rewrite (ADR-0060); `checked={count region == 0}` attributes become
`regionChecked% "region"` and `checked={count region (field == "literal") == 0}`
attributes become `regionChecked% "region" fieldIndex "literal"` before
lowering. Every other dynamic `checked` value keeps its ADR-0038 controlled
reflection meaning. -/
scoped syntax (name := leanrxJsxAttrRegionChecked)
  "regionChecked%" str (num str)? : leanrxJsxAttr
/- Internal target of the component command's prop-forwarding rewrite
(ADR-0068); a child element attribute `name={parentProp}` whose value is one
of the parent's declared immutable props becomes `name = propRef% index`
before lowering, carrying the parent's prop declaration index. -/
scoped syntax (name := leanrxJsxAttrPropRef) ident "=" "propRef%" num : leanrxJsxAttr

declare_syntax_cat leanrxJsxChild
declare_syntax_cat leanrxJsxElement
declare_syntax_cat leanrxJsxKeyed
scoped syntax str : leanrxJsxChild
scoped syntax "{" str ":" term "}" : leanrxJsxChild
scoped syntax (name := leanrxJsxChildDynamic) "{" term "}" : leanrxJsxChild
/- Internal target of the component command's immutable-prop rewrite
(ADR-0042); `{propName}` children become `propText% index` before lowering. -/
scoped syntax (name := leanrxJsxPropText) "propText%" num : leanrxJsxChild
/- Internal target of the component command's sealed row aggregate rewrite
(ADR-0050); `{count region}` children become `regionCount% "region"` and
`{count region (field == "literal")}` children become
`regionCount% "region" fieldIndex "literal"` before lowering. -/
scoped syntax (name := leanrxJsxRegionCount)
  "regionCount%" str (num str)? : leanrxJsxChild
/- Internal target of the component command's sealed count-label rewrite
(ADR-0062); `{if count region == 1 then "one" else "other"}` children become
`regionCountLabel% "region" "one" "other"` and
`{if count region (field == "literal") == 1 then "one" else "other"}`
children become `regionCountLabel% "region" fieldIndex "literal" "one"
"other"` before lowering. -/
scoped syntax (name := leanrxJsxRegionCountLabel)
  "regionCountLabel%" str (num str)? str str : leanrxJsxChild
scoped syntax leanrxJsxElement : leanrxJsxChild
/- The sealed two-branch row cell (ADR-0047): valid only inside `region` row
templates, where the component command lowers it to `RowNode.branch`. -/
scoped syntax (name := leanrxJsxBranchChild)
  "{" "if" ident "==" str "then" leanrxJsxElement "else" leanrxJsxElement "}" : leanrxJsxChild
scoped syntax "for " ident " in " term " key " term " => " leanrxJsxElement : leanrxJsxKeyed
scoped syntax leanrxJsxKeyed : leanrxJsxChild
scoped syntax "<" ident leanrxJsxAttr* ">" "[" leanrxJsxChild,* "]" : leanrxJsxElement
scoped syntax "<" ident leanrxJsxAttr* "/>" : leanrxJsxElement
/- A keyed region slot (ADR-0041); the name must be declared by a `region`
item of the enclosing component. -/
scoped syntax (name := leanrxJsxRegionSlot) "<" &"region" ident "/>" : leanrxJsxElement

open scoped LeanRxDsl

syntax "leanrx_jsx_tag% " ident : term
macro_rules
  | `(leanrx_jsx_tag% main) => `(LeanRx.HtmlTag.main)
  | `(leanrx_jsx_tag% div) => `(LeanRx.HtmlTag.div)
  | `(leanrx_jsx_tag% button) => `(LeanRx.HtmlTag.button)
  | `(leanrx_jsx_tag% p) => `(LeanRx.HtmlTag.p)
  | `(leanrx_jsx_tag% span) => `(LeanRx.HtmlTag.span)
  | `(leanrx_jsx_tag% h1) => `(LeanRx.HtmlTag.h1)
  | `(leanrx_jsx_tag% h2) => `(LeanRx.HtmlTag.h2)
  | `(leanrx_jsx_tag% h3) => `(LeanRx.HtmlTag.h3)
  | `(leanrx_jsx_tag% header) => `(LeanRx.HtmlTag.header)
  | `(leanrx_jsx_tag% footer) => `(LeanRx.HtmlTag.footer)
  | `(leanrx_jsx_tag% nav) => `(LeanRx.HtmlTag.nav)
  | `(leanrx_jsx_tag% aside) => `(LeanRx.HtmlTag.aside)
  | `(leanrx_jsx_tag% article) => `(LeanRx.HtmlTag.article)
  | `(leanrx_jsx_tag% ul) => `(LeanRx.HtmlTag.ul)
  | `(leanrx_jsx_tag% li) => `(LeanRx.HtmlTag.li)
  | `(leanrx_jsx_tag% pre) => `(LeanRx.HtmlTag.pre)
  | `(leanrx_jsx_tag% code) => `(LeanRx.HtmlTag.code)
  | `(leanrx_jsx_tag% input) => `(LeanRx.HtmlTag.input)
  | `(leanrx_jsx_tag% label) => `(LeanRx.HtmlTag.label)
  | `(leanrx_jsx_tag% strong) => `(LeanRx.HtmlTag.strong)
  | `(leanrx_jsx_tag% em) => `(LeanRx.HtmlTag.em)
  | `(leanrx_jsx_tag% form) => `(LeanRx.HtmlTag.form)
  | `(leanrx_jsx_tag% $unknown:ident) =>
      Macro.throwErrorAt unknown s!"error[LRX-VIEW-007]: unsupported element <{unknown.getId}>"

syntax "leanrx_jsx_attr% " leanrxJsxAttr : term
macro_rules
  | `(leanrx_jsx_attr% class = $value:str) =>
      `(LeanRx.ViewAttr.static (.className $value))
  | `(leanrx_jsx_attr% id = $value:str) =>
      `(LeanRx.ViewAttr.static (.id $value))
  | `(leanrx_jsx_attr% ariaLabel = $value:str) =>
      `(LeanRx.ViewAttr.static (.ariaLabel $value))
  | `(leanrx_jsx_attr% type = "button") =>
      `(LeanRx.ViewAttr.static (.buttonType .button))
  | `(leanrx_jsx_attr% type = "submit") =>
      `(LeanRx.ViewAttr.static (.buttonType .submit))
  | `(leanrx_jsx_attr% type = "reset") =>
      `(LeanRx.ViewAttr.static (.buttonType .reset))
  | `(leanrx_jsx_attr% type = "text") =>
      `(LeanRx.ViewAttr.static (.inputType .text))
  | `(leanrx_jsx_attr% type = "checkbox") =>
      `(LeanRx.ViewAttr.static (.inputType .checkbox))
  | `(leanrx_jsx_attr% type = $value:str) =>
      Macro.throwErrorAt value
        s!"error[LRX-VIEW-008]: unknown or invalid type attribute value {value.getString}"
  | `(leanrx_jsx_attr% onClick = $event:str) =>
      `(LeanRx.ViewAttr.event { kind := .click, eventName := $event })
  | `(leanrx_jsx_attr% onDblClick = $event:str) =>
      `(LeanRx.ViewAttr.event { kind := .dblclick, eventName := $event })
  | `(leanrx_jsx_attr% onInput = $event:str) =>
      `(LeanRx.ViewAttr.event { kind := .input, eventName := $event })
  | `(leanrx_jsx_attr% onKeyDown = $event:str) =>
      `(LeanRx.ViewAttr.event { kind := .keydown, eventName := $event })
  | `(leanrx_jsx_attr% onChange = $event:str) =>
      `(LeanRx.ViewAttr.event { kind := .change, eventName := $event })
  | `(leanrx_jsx_attr% role = $value:str) =>
      `(LeanRx.ViewAttr.static (.role $value))
  | `(leanrx_jsx_attr% placeholder = $value:str) =>
      `(LeanRx.ViewAttr.static (.placeholder $value))
  | `(leanrx_jsx_attr% rawHtml = $_:str) =>
      Macro.throwError "error[LRX-VIEW-010]: raw HTML is excluded from the safe view DSL"
  | `(leanrx_jsx_attr% $name:ident = $_:str) =>
      Macro.throwErrorAt name s!"error[LRX-VIEW-008]: unknown or invalid view attribute {name.getId}"
  | `(leanrx_jsx_attr% autoFocus) =>
      Macro.throwError
        "error[LRX-VIEW-036]: an autoFocus marker is available on inputs inside sealed row branch subtrees only (ADR-0048)"
  | `(leanrx_jsx_attr% $name:ident) =>
      Macro.throwErrorAt name s!"error[LRX-VIEW-008]: unknown or invalid view attribute {name.getId}"

scoped syntax (name := leanrxJsxTerm) "jsx% " leanrxJsxElement : term
scoped syntax (name := leanrxJsxKeyedTerm) "jsx% " leanrxJsxKeyed : term
syntax "leanrx_jsx_typed% " leanrxJsxElement : term
syntax "leanrx_jsx_logical% " leanrxJsxElement : term
syntax "leanrx_jsx_logical_keyed% " leanrxJsxKeyed : term
syntax "leanrx_jsx_child% " leanrxJsxChild : term

/-- Wrap one nested-component prop: when the component declares the prop as an
M6 `ImmutableProp`, the attribute name and value stage through
`ImmutableProp.of`; otherwise the value elaborates directly against the
declared prop type. -/
elab "leanrx_jsx_prop% " name:str value:term : term <= expectedType => do
  let target ← whnf (← instantiateMVars expectedType)
  if target.isAppOf ``LeanRx.ImmutableProp then
    Term.elabTerm (← `(LeanRx.ImmutableProp.of $name $value)) expectedType
  else
    Term.elabTerm value expectedType

/-- A capitalized element head nests another component by typed application. -/
def componentHead? (tag : TSyntax `ident) : Bool :=
  match tag.getId.eraseMacroScopes with
  | .str _ shortName => shortName.length > 0 && shortName.front.isUpper
  | _ => false

def componentShortName (tag : TSyntax `ident) : String :=
  match tag.getId.eraseMacroScopes with
  | .str _ shortName => shortName
  | other => other.toString

/-- The `component` command generates `{name}_spec` beside each checked
component; a capitalized JSX head resolves against that convention. -/
def resolvesToComponentSpec (tag : TSyntax `ident) : TermElabM Bool := do
  let specIdent := mkIdentFrom tag (tag.getId.appendAfter "_spec")
  try
    pure (← Term.resolveId? specIdent).isSome
  catch _ =>
    pure false

/-- Evaluate the declared immutable prop names of the checked component
`{tag}_spec` (ADR-0042). This isolated compile-time evaluation mirrors the
component command's validation-message evaluation. -/
def componentPropNames (tag : TSyntax `ident) : TermElabM (List String) := do
  let specIdent := mkIdentFrom tag (tag.getId.appendAfter "_spec")
  let listString := mkApp (mkConst ``List [Level.zero]) (mkConst ``String)
  let expression ← Term.elabTermEnsuringType
    (← `(LeanRx.ComponentSpec.propNames $specIdent)) listString
  Term.synthesizeSyntheticMVarsNoPostponing
  let expression ← instantiateMVars expression
  unsafe Meta.evalExpr (checkMeta := false) (List String) listString expression

/-- Evaluate the checked component `{tag}_spec`'s static-id trail (ADR-0090),
mirroring the prop-names compile-time evaluation: the chain of component
names from `{tag}` down to the first component in its mounted tree carrying a
static `id`, empty when the whole tree is id-free. A row-composed child mounts
one instance per row, so the parent-side row lowering rejects a non-empty
trail and names the path. The trail is read off the spec rather than walked
here: the grandchildren of `{tag}` are names in its child table, and nothing
puts their specs in scope at this elaboration site. -/
def componentStaticIdTrail (tag : TSyntax `ident) : TermElabM (List String) := do
  let specIdent := mkIdentFrom tag (tag.getId.appendAfter "_spec")
  let listString := mkApp (mkConst ``List [Level.zero]) (mkConst ``String)
  let expression ← Term.elabTermEnsuringType
    (← `(LeanRx.ComponentSpec.staticIdTrail $specIdent)) listString
  Term.synthesizeSyntheticMVarsNoPostponing
  let expression ← instantiateMVars expression
  unsafe Meta.evalExpr (checkMeta := false) (List String) listString expression

private def renderNames (names : List String) : String :=
  String.intercalate ", " names

/-- An attr-less capitalized self-closing element statically nests the checked
component `{name}_spec` when one is in scope (ADR-0039); otherwise it keeps the
existing behavior and elaborates the identifier as an ordinary view term. -/
elab "leanrx_jsx_component% " name:ident marker:str : term <= expectedType => do
  if ← resolvesToComponentSpec name then
    let declared ← componentPropNames name
    unless declared.isEmpty do
      throwErrorAt name
        s!"error[LRX-ELAB-112]: child component {componentShortName name} declares immutable props ({renderNames declared}); pass them as attributes"
    let nameLit := Syntax.mkStrLit (componentShortName name)
    Term.elabTerm
      (← `(LeanRx.View.child $nameLit (leanrx_source_span% $marker))) expectedType
  else
    Term.elabTerm name expectedType

/-- A capitalized self-closing element whose attributes are all `name="text"`
or `name = propRef% index` nests the checked component `{name}_spec` with
immutable prop values when one is in scope (ADR-0042); the bindings must match
the child's declared prop names and order exactly. A `propRef%` value forwards
one of the parent's own immutable props by declaration index (ADR-0068) —
still a mount-time constant — and has no typed-application meaning, so it
requires the checked spec. Without one, literal bindings stay an ordinary
typed component call. -/
elab "leanrx_jsx_component_props% " name:ident marker:str pairs:(str <|> num)* : term <= expectedType => do
  let bindings := (List.range (pairs.size / 2)).map fun index =>
    ((pairs[2 * index]!).raw, (pairs[2 * index + 1]!).raw)
  let boundNames := bindings.map fun (bound, _) => (bound.isStrLit?).getD ""
  if ← resolvesToComponentSpec name then
    let declared ← componentPropNames name
    unless boundNames == declared do
      throwErrorAt name
        s!"error[LRX-ELAB-112]: child component {componentShortName name} declares immutable props ({renderNames declared}); got ({renderNames boundNames}) — bindings must match the declaration names and order"
    let nameLit := Syntax.mkStrLit (componentShortName name)
    let pairTerms ← bindings.mapM fun (bound, value) => do
      let boundLit : TSyntax `str := ⟨bound⟩
      if value.isStrLit?.isSome then
        `(($boundLit, LeanRx.ChildProp.lit $(⟨value⟩)))
      else
        `(($boundLit, LeanRx.ChildProp.forward $(⟨value⟩)))
    Term.elabTerm (← `(LeanRx.View.child $nameLit (leanrx_source_span% $marker)
      (props := [$(pairTerms.toArray),*]))) expectedType
  else
    let mut result : TSyntax `term := ⟨name.raw⟩
    for ((bound, value), boundName) in bindings.zip boundNames do
      if value.isStrLit?.isNone then
        throwErrorAt name
          s!"error[LRX-ELAB-130]: {componentShortName name} does not resolve to a checked component spec; forwarding a parent prop with {boundName}=\{…} nests checked child components only"
      let boundIdent := mkIdentFrom name (Name.mkSimple boundName)
      let boundLit : TSyntax `str := ⟨bound⟩
      result ← `($result ($boundIdent:ident := leanrx_jsx_prop% $boundLit $(⟨value⟩)))
    Term.elabTerm result expectedType

/-- The typed-application fallback for a capitalized head whose attributes or
children do not form a child reference (empty children with `name="text"` or
rewritten `name = propRef% index` attributes only). A head without a checked
spec keeps its ordinary typed-application meaning (ADR-0039), but a head that
resolves to `{name}_spec` has no ordinary meaning — the component command
generates the spec, not a term named `{name}` — so the application below
could only die with an unresolved-identifier error. Reject the misshapen
reference here, where the spec is visible, with the composition contract
instead (ADR-0073). The ordinary application never consumed JSX children
either — `componentCall` receives attributes only — so non-empty children on
a spec-less head could only vanish silently; reject that shape too instead
of dropping content (ADR-0074). -/
elab "leanrx_jsx_component_fallback% " name:ident reason:str childCount:num call:term : term <= expectedType => do
  if ← resolvesToComponentSpec name then
    throwErrorAt name
      s!"error[LRX-ELAB-132]: {componentShortName name} resolves to the checked component spec {componentShortName name}_spec; {reason.getString}"
  else if childCount.getNat != 0 then
    throwErrorAt name
      s!"error[LRX-ELAB-133]: {componentShortName name} does not resolve to a checked component spec; a spec-less capitalized head is an ordinary application (ADR-0039) and consumes no children — its content is the application's own result, so the children here would be dropped"
  else
    Term.elabTerm call expectedType

private def componentCall (tag : TSyntax `ident) (attrs : Array Syntax) :
    MacroM (TSyntax `term) := do
  let mut result : TSyntax `term := ⟨tag.raw⟩
  for attr in attrs do
    let attrStx : TSyntax `leanrxJsxAttr := ⟨attr⟩
    match attrStx with
    | `(leanrxJsxAttr| $name:ident = $value:str) =>
        let nameLit := Syntax.mkStrLit name.getId.toString
        result ← `($result ($name:ident := leanrx_jsx_prop% $nameLit $value))
    | `(leanrxJsxAttr| $name:ident = { $value:term }) =>
        let nameLit := Syntax.mkStrLit name.getId.toString
        result ← `($result ($name:ident := leanrx_jsx_prop% $nameLit $value))
    | _ =>
        Macro.throwErrorAt attr
          "error[LRX-VIEW-014]: component props are written name=\"text\" or name={value}"
  pure result

macro_rules
  | `(leanrx_jsx_child% $value:str) => `(LeanRx.View.text $value)
  | `(leanrx_jsx_child% { $name:str : $value:term }) =>
      `(LeanRx.View.scalarText $name $value)
  | `(leanrx_jsx_child% $element:leanrxJsxElement) => `(leanrx_jsx_typed% $element)

/-- The `name="text"` and rewritten `name = propRef% index` pairs of one
attribute array, when every attribute has one of those shapes — the only
shapes that can carry immutable child props: literals (ADR-0042) and
forwarded parent props (ADR-0068). -/
private def literalPropPairs (attrs : Array Syntax) :
    Option (Array (TSyntax [`str, `num])) := Id.run do
  let mut pairs : Array (TSyntax [`str, `num]) := #[]
  for attr in attrs do
    let attrStx : TSyntax `leanrxJsxAttr := ⟨attr⟩
    match attrStx with
    | `(leanrxJsxAttr| $name:ident = $value:str) =>
        pairs := pairs.push ⟨Syntax.mkStrLit name.getId.toString (info := name.raw.getHeadInfo)⟩
        pairs := pairs.push ⟨value.raw⟩
    | `(leanrxJsxAttr| $name:ident = propRef% $index:num) =>
        pairs := pairs.push ⟨Syntax.mkStrLit name.getId.toString (info := name.raw.getHeadInfo)⟩
        pairs := pairs.push ⟨index.raw⟩
    | _ => return none
  return some pairs

private def typedElement (tag : TSyntax `ident) (attrs : Array Syntax)
    (children : Array Syntax) (span : Syntax) : MacroM (TSyntax `term) := do
  if componentHead? tag then
    if attrs.isEmpty && children.isEmpty then
      `(leanrx_jsx_component% $tag $(spanMarker span))
    else match (if children.isEmpty then literalPropPairs attrs else none) with
      | some pairs => `(leanrx_jsx_component_props% $tag $(spanMarker span) $pairs*)
      | none =>
          let reason := Syntax.mkStrLit <| if children.isEmpty then
              "a child reference passes immutable props only — name=\"text\" literals (ADR-0042) or one forwarded parent prop name={prop} (ADR-0068); events and composed values stay inside the child's own view"
            else
              "a child reference takes no children — the child's content lives in its own component view"
          let count : TSyntax `num := Syntax.mkNumLit (toString children.size)
          let call ← componentCall tag attrs
          `(leanrx_jsx_component_fallback% $tag $reason $count $call)
  else do
    let mut propTerms : Array (TSyntax `term) := #[]
    for attr in attrs do
      let attrSyntax : TSyntax `leanrxJsxAttr := ⟨attr⟩
      match attrSyntax with
      | `(leanrxJsxAttr| value = { $expr:term }) => do
          let span ← spanSyntax attr
          propTerms := propTerms.push (← `(LeanRx.PropBinding.value $expr $span))
      | `(leanrxJsxAttr| checked = { $expr:term }) => do
          let span ← spanSyntax attr
          propTerms := propTerms.push (← `(LeanRx.PropBinding.checked $expr $span))
      | _ => pure ()
    /- Sealed state-scoped attribute selections (ADR-0045): `class` takes the
    two-branch equality conditional, `aria-pressed`/`disabled` take the bare
    equality; the field is an ordinary schema `Field` reference. The subject
    may sit behind the one sealed trim unary (ADR-0057), matched by name so
    `trim` stays an ordinary identifier (ADR-0035); any other applied head is
    a rejected predicate, not a selection. -/
    let requireTrimHead (attr : Syntax) (head : TSyntax `ident) : MacroM Unit := do
      unless head.getId.eraseMacroScopes == `trim do
        Macro.throwErrorAt attr
          "error[LRX-VIEW-012]: a selection subject is one state field, raw or behind the one trim unary (ADR-0057); general predicates are not selections"
    let mut selectTerms : Array (TSyntax `term) := #[]
    for attr in attrs do
      let attrSyntax : TSyntax `leanrxJsxAttr := ⟨attr⟩
      match attrSyntax with
      | `(leanrxJsxAttr| class = {
            if $field:ident == $lit:str then $whenTrue:str else $whenFalse:str }) => do
          let span ← spanSyntax attr
          selectTerms := selectTerms.push
            (← `(LeanRx.AttrSelect.classSelect $field $lit $whenTrue $whenFalse $span))
      | `(leanrxJsxAttr| class = {
            if $head:ident $field:ident == $lit:str
              then $whenTrue:str else $whenFalse:str }) => do
          requireTrimHead attr head
          let span ← spanSyntax attr
          selectTerms := selectTerms.push
            (← `(LeanRx.AttrSelect.classSelect $field $lit $whenTrue $whenFalse $span
              (trimmed := true)))
      | `(leanrxJsxAttr| ariaPressed = { $field:ident == $lit:str }) => do
          let span ← spanSyntax attr
          selectTerms := selectTerms.push
            (← `(LeanRx.AttrSelect.pressedSelect $field $lit $span))
      | `(leanrxJsxAttr| ariaPressed = { $head:ident $field:ident == $lit:str }) => do
          requireTrimHead attr head
          let span ← spanSyntax attr
          selectTerms := selectTerms.push
            (← `(LeanRx.AttrSelect.pressedSelect $field $lit $span (trimmed := true)))
      | `(leanrxJsxAttr| disabled = { $field:ident == $lit:str }) => do
          let span ← spanSyntax attr
          selectTerms := selectTerms.push
            (← `(LeanRx.AttrSelect.disabledSelect $field $lit $span))
      | `(leanrxJsxAttr| disabled = { $head:ident $field:ident == $lit:str }) => do
          requireTrimHead attr head
          let span ← spanSyntax attr
          selectTerms := selectTerms.push
            (← `(LeanRx.AttrSelect.disabledSelect $field $lit $span (trimmed := true)))
      | `(leanrxJsxAttr| regionHidden% $region:str) => do
          /- The sealed empty-region visibility selection (ADR-0058), produced
          only by the component command's rewrite, which already resolved the
          region name and the zero literal. -/
          let span ← spanSyntax attr
          selectTerms := selectTerms.push
            (← `(LeanRx.AttrSelect.hiddenIfEmpty $region $span))
      | `(leanrxJsxAttr| regionHidden% $region:str $field:num $lit:str) => do
          /- The sealed predicate-count visibility selection (ADR-0059): the
          rewrite already resolved the region name, the projected field's
          index, and the zero literal. -/
          let span ← spanSyntax attr
          selectTerms := selectTerms.push
            (← `(LeanRx.AttrSelect.hiddenIfEmpty $region $span
              (predicate := some ($field, $lit))))
      | `(leanrxJsxAttr| regionChecked% $region:str) => do
          /- The sealed toggle-all checked selection (ADR-0060), produced only
          by the component command's rewrite over the same count surface. -/
          let span ← spanSyntax attr
          selectTerms := selectTerms.push
            (← `(LeanRx.AttrSelect.checkedIfEmpty $region $span))
      | `(leanrxJsxAttr| regionChecked% $region:str $field:num $lit:str) => do
          /- The predicate-count checked selection (ADR-0060): the rewrite
          already resolved the region name, the projected field's index, and
          the zero literal. -/
          let span ← spanSyntax attr
          selectTerms := selectTerms.push
            (← `(LeanRx.AttrSelect.checkedIfEmpty $region $span
              (predicate := some ($field, $lit))))
      | _ => pure ()
    let plainAttrs := attrs.filter fun attr =>
      let attrSyntax : TSyntax `leanrxJsxAttr := ⟨attr⟩
      match attrSyntax with
      | `(leanrxJsxAttr| value = { $_:term }) | `(leanrxJsxAttr| checked = { $_:term }) => false
      | `(leanrxJsxAttr| class = {
            if $_:ident == $_:str then $_:str else $_:str }) => false
      | `(leanrxJsxAttr| class = {
            if $_:ident $_:ident == $_:str then $_:str else $_:str }) => false
      | `(leanrxJsxAttr| ariaPressed = { $_:ident == $_:str }) => false
      | `(leanrxJsxAttr| ariaPressed = { $_:ident $_:ident == $_:str }) => false
      | `(leanrxJsxAttr| disabled = { $_:ident == $_:str }) => false
      | `(leanrxJsxAttr| disabled = { $_:ident $_:ident == $_:str }) => false
      | `(leanrxJsxAttr| regionHidden% $_:str) => false
      | `(leanrxJsxAttr| regionHidden% $_:str $_:num $_:str) => false
      | `(leanrxJsxAttr| regionChecked% $_:str) => false
      | `(leanrxJsxAttr| regionChecked% $_:str $_:num $_:str) => false
      | _ => true
    let attrTerms ← plainAttrs.mapM fun attr =>
      let attrSyntax : TSyntax `leanrxJsxAttr := ⟨attr⟩
      match attrSyntax with
      | `(leanrxJsxAttr| onClick = $event:str) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.click, eventName := $event, span := $span
          })
      | `(leanrxJsxAttr| onDblClick = $event:str) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.dblclick, eventName := $event, span := $span
          })
      | `(leanrxJsxAttr| onInput = $event:str) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.input, eventName := $event, span := $span
          })
      | `(leanrxJsxAttr| onKeyDown = $event:str) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.keydown, eventName := $event, span := $span
          })
      | `(leanrxJsxAttr| onChange = $event:str) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.change, eventName := $event, span := $span
          })
      | `(leanrxJsxAttr| onClick = { $event:term }) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.click
            eventName := LeanRx.EventSpec.name $event, span := $span
          })
      | `(leanrxJsxAttr| onDblClick = { $event:term }) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.dblclick
            eventName := LeanRx.EventSpec.name $event, span := $span
          })
      | `(leanrxJsxAttr| onInput = { $event:term }) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.input
            eventName := LeanRx.TypedEventSpec.name $event, span := $span
          })
      | `(leanrxJsxAttr| onKeyDown = { $event:term }) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.keydown
            eventName := LeanRx.TypedEventSpec.name $event, span := $span
          })
      | `(leanrxJsxAttr| onChange = { $event:term }) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.change
            eventName := LeanRx.TypedEventSpec.name $event, span := $span
          })
      | `(leanrxJsxAttr| onCheckedChange = $event:str) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.checkedChange, eventName := $event, span := $span
          })
      | `(leanrxJsxAttr| onCheckedChange = { $event:term }) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.checkedChange
            eventName := LeanRx.TypedEventSpec.name $event, span := $span
          })
      | `(leanrxJsxAttr| onSubmit = $event:str) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.submit, eventName := $event, span := $span
          })
      | `(leanrxJsxAttr| onSubmit = { $event:term }) => do
          let span ← spanSyntax attr
          `(LeanRx.ViewAttr.event {
            kind := LeanRx.EventKind.submit
            eventName := LeanRx.EventSpec.name $event, span := $span
          })
      | `(leanrxJsxAttr| class = { $_:term }) =>
          Macro.throwErrorAt attr
            "error[LRX-VIEW-012]: a state-scoped class selection is written class={if field == \"literal\" then \"a\" else \"b\"} or class={if trim field == \"literal\" then \"a\" else \"b\"} (ADR-0045/0057); other dynamic attribute values require the logical reference view"
      | `(leanrxJsxAttr| type = { $_:term }) =>
          Macro.throwErrorAt attr
            "error[LRX-VIEW-012]: dynamic attribute values require the logical reference view"
      | `(leanrxJsxAttr| ariaPressed = { $_:term }) =>
          Macro.throwErrorAt attr
            "error[LRX-VIEW-012]: a state-scoped aria-pressed selection is written ariaPressed={field == \"literal\"} or ariaPressed={trim field == \"literal\"} (ADR-0045/0057)"
      | `(leanrxJsxAttr| disabled = { $_:term }) =>
          Macro.throwErrorAt attr
            "error[LRX-VIEW-012]: a state-scoped disabled selection is written disabled={field == \"literal\"} or disabled={trim field == \"literal\"} (ADR-0045/0057)"
      | `(leanrxJsxAttr| hidden = { $_:term }) =>
          Macro.throwErrorAt attr
            "error[LRX-VIEW-012]: a hidden reflection is written hidden={count region == 0} on a component view element (ADR-0058)"
      | `(leanrxJsxAttr| $_:ident = { $_:term }) =>
          Macro.throwErrorAt attr
            "error[LRX-VIEW-012]: dynamic attribute values require the logical reference view"
      | _ => `(leanrx_jsx_attr% $attrSyntax)
    let childTerms ← children.mapM fun child =>
      let childStx : TSyntax `leanrxJsxChild := ⟨child⟩
      match childStx with
      | `(leanrxJsxChild| $value:str) => do
          let span ← spanSyntax child
          `(LeanRx.View.text $value $span)
      | `(leanrxJsxChild| { $name:str : $value:term }) => do
          let span ← spanSyntax child
          `(LeanRx.View.scalarText $name $value $span)
      | `(leanrxJsxChild| propText% $index:num) => do
          let span ← spanSyntax child
          `(LeanRx.View.propText $index $span)
      | `(leanrxJsxChild| regionCount% $region:str) => do
          let span ← spanSyntax child
          `(LeanRx.View.regionCount $region none $span)
      | `(leanrxJsxChild| regionCount% $region:str $index:num $lit:str) => do
          let span ← spanSyntax child
          `(LeanRx.View.regionCount $region (some ($index, $lit)) $span)
      | `(leanrxJsxChild| regionCountLabel% $region:str $one:str $other:str) => do
          let span ← spanSyntax child
          `(LeanRx.View.regionCount $region none $span (some ($one, $other)))
      | `(leanrxJsxChild| regionCountLabel% $region:str $index:num $lit:str
            $one:str $other:str) => do
          let span ← spanSyntax child
          `(LeanRx.View.regionCount $region (some ($index, $lit)) $span
            (some ($one, $other)))
      | `(leanrxJsxChild| { $_:term }) =>
          Macro.throwErrorAt child
            "error[LRX-VIEW-012]: unnamed dynamic text requires the logical reference view"
      | `(leanrxJsxChild| { if $_:ident == $_:str then $_:leanrxJsxElement
            else $_:leanrxJsxElement }) =>
          Macro.throwErrorAt child
            "error[LRX-VIEW-034]: a two-branch cell is available inside sealed row templates only (ADR-0047)"
      | `(leanrxJsxChild| $_:leanrxJsxKeyed) =>
          Macro.throwErrorAt child
            "error[LRX-VIEW-011]: keyed list children require the logical reference view"
      | `(leanrxJsxChild| $nested:leanrxJsxElement) => `(leanrx_jsx_typed% $nested)
      | _ => Macro.throwErrorAt child "error[LRX-VIEW-009]: malformed LeanRx JSX child"
    let spanTerm ← spanSyntax span
    `(LeanRx.View.nodeWith (leanrx_jsx_tag% $tag) [$childTerms,*]
      (attrs := [$attrTerms,*]) (span := $spanTerm) (props := [$propTerms,*])
      (selects := [$selectTerms,*]))

macro_rules
  | `(leanrx_jsx_typed% $element:leanrxJsxElement) => do
      match element with
      | `(leanrxJsxElement| <region $name:ident />) => do
          let nameLit := Syntax.mkStrLit name.getId.eraseMacroScopes.toString
            (info := name.raw.getHeadInfo)
          let spanTerm ← spanSyntax element
          `(LeanRx.View.region $nameLit $spanTerm)
      | `(leanrxJsxElement| <$tag:ident $attrs:leanrxJsxAttr* >
            [$children:leanrxJsxChild,*]) =>
          typedElement tag attrs children.getElems element
      | `(leanrxJsxElement| <$tag:ident $attrs:leanrxJsxAttr* />) =>
          typedElement tag attrs #[] element
      | _ => Macro.throwErrorAt element "error[LRX-VIEW-009]: malformed LeanRx JSX element"

/-- Map one surface attribute name onto the closed logical attribute
vocabulary. `data`-prefixed camelCase idents become `data-*` attributes. -/
private def logicalAttrName (name : TSyntax `ident) : MacroM String := do
  let text := name.getId.toString
  match text with
  | "role" | "placeholder" | "value" | "filter" => pure text
  | _ =>
    if text.startsWith "data" && text.length > 4 &&
        (text.drop 4).toString.front.isUpper then
      let rest := (text.drop 4).toString
      pure <| rest.toList.foldl (init := "data") fun acc char =>
        if char.isUpper then acc ++ "-" ++ char.toLower.toString
        else acc.push char
    else
      Macro.throwErrorAt name
        s!"error[LRX-VIEW-008]: unknown or invalid view attribute {name.getId}"

private def logicalAttr (attr : Syntax) : MacroM (TSyntax `term) := do
  let attrStx : TSyntax `leanrxJsxAttr := ⟨attr⟩
  match attrStx with
  | `(leanrxJsxAttr| class = $value:str) => `(("class", $value))
  | `(leanrxJsxAttr| class = { $value:term }) => `(("class", ($value : String)))
  | `(leanrxJsxAttr| id = $value:str) => `(("id", $value))
  | `(leanrxJsxAttr| id = { $value:term }) => `(("id", ($value : String)))
  | `(leanrxJsxAttr| ariaLabel = $value:str) => `(("aria-label", $value))
  | `(leanrxJsxAttr| ariaLabel = { $value:term }) => `(("aria-label", ($value : String)))
  | `(leanrxJsxAttr| type = $value:str) => `(("type", $value))
  | `(leanrxJsxAttr| type = { $value:term }) => `(("type", ($value : String)))
  | `(leanrxJsxAttr| onClick = $_:str) | `(leanrxJsxAttr| onClick = { $_:term })
  | `(leanrxJsxAttr| onDblClick = $_:str) | `(leanrxJsxAttr| onDblClick = { $_:term })
  | `(leanrxJsxAttr| onInput = $_:str) | `(leanrxJsxAttr| onInput = { $_:term })
  | `(leanrxJsxAttr| onKeyDown = $_:str) | `(leanrxJsxAttr| onKeyDown = { $_:term })
  | `(leanrxJsxAttr| onChange = $_:str) | `(leanrxJsxAttr| onChange = { $_:term })
  | `(leanrxJsxAttr| onCheckedChange = $_:str)
  | `(leanrxJsxAttr| onCheckedChange = { $_:term })
  | `(leanrxJsxAttr| onSubmit = $_:str) | `(leanrxJsxAttr| onSubmit = { $_:term }) =>
      Macro.throwErrorAt attr
        "error[LRX-VIEW-013]: event bindings are not representable in the logical reference view"
  | `(leanrxJsxAttr| $name:ident = $value:str) => do
      let mapped := Syntax.mkStrLit (← logicalAttrName name)
      `(($mapped, $value))
  | `(leanrxJsxAttr| $name:ident = { $value:term }) => do
      let mapped := Syntax.mkStrLit (← logicalAttrName name)
      `(($mapped, ($value : String)))
  | `(leanrxJsxAttr| $name:ident) =>
      if name.getId.eraseMacroScopes == `autoFocus then
        Macro.throwErrorAt name
          "error[LRX-VIEW-036]: an autoFocus marker is available on inputs inside sealed row branch subtrees only (ADR-0048)"
      else
        Macro.throwErrorAt name
          s!"error[LRX-VIEW-008]: unknown or invalid view attribute {name.getId}"
  | _ => Macro.throwErrorAt attr "error[LRX-VIEW-009]: malformed LeanRx JSX attribute"

/-- Lower logical children into one `List LogicalNode` term. Runs of plain
children become list literals; keyed segments splice through the keyed region
IR with `KeyedItem.nodes`; a lone segment is used directly. -/
private def logicalChildren (children : Array Syntax) : MacroM (TSyntax `term) := do
  let mut segments : Array (TSyntax `term) := #[]
  let mut plain : Array (TSyntax `term) := #[]
  for child in children do
    let childStx : TSyntax `leanrxJsxChild := ⟨child⟩
    match childStx with
    | `(leanrxJsxChild| $value:str) =>
        plain := plain.push (← `(LeanRx.Region.LogicalNode.text $value))
    | `(leanrxJsxChild| { $_:str : $_:term }) =>
        Macro.throwErrorAt child
          "error[LRX-VIEW-015]: named text sinks require the typed component view"
    | `(leanrxJsxChild| { $value:term }) =>
        plain := plain.push (← `(LeanRx.Region.LogicalNode.text ($value : String)))
    | `(leanrxJsxChild| { if $_:ident == $_:str then $_:leanrxJsxElement
          else $_:leanrxJsxElement }) =>
        Macro.throwErrorAt child
          "error[LRX-VIEW-034]: a two-branch cell is available inside sealed row templates only (ADR-0047)"
    | `(leanrxJsxChild| $keyed:leanrxJsxKeyed) => do
        if !plain.isEmpty then
          segments := segments.push (← `([$plain,*]))
          plain := #[]
        segments := segments.push
          (← `(LeanRx.Region.KeyedItem.nodes (leanrx_jsx_logical_keyed% $keyed)))
    | `(leanrxJsxChild| $nested:leanrxJsxElement) =>
        plain := plain.push (← `(leanrx_jsx_logical% $nested))
    | _ => Macro.throwErrorAt child "error[LRX-VIEW-009]: malformed LeanRx JSX child"
  if !plain.isEmpty || segments.isEmpty then
    segments := segments.push (← `([$plain,*]))
  let mut result := segments[0]!
  for segment in segments[1:] do
    result ← `($result ++ $segment)
  pure result

private def logicalElement (tag : TSyntax `ident) (attrs : Array Syntax)
    (children : Array Syntax) : MacroM (TSyntax `term) := do
  if componentHead? tag then
    -- Same guard as the typed fallback (ADR-0074): a spec'd head has no
    -- ordinary meaning here either, and a spec-less head's children would
    -- vanish — `componentCall` receives attributes only.
    let reason := Syntax.mkStrLit
      "checked components nest in the typed component view only — the logical reference view lowers ordinary applications"
    let count : TSyntax `num := Syntax.mkNumLit (toString children.size)
    let call ← componentCall tag attrs
    `(leanrx_jsx_component_fallback% $tag $reason $count $call)
  else do
    let attrTerms ← attrs.mapM logicalAttr
    let childrenTerm ← logicalChildren children
    `(LeanRx.Region.LogicalNode.element
      (LeanRx.HtmlTag.name (leanrx_jsx_tag% $tag)) [$attrTerms,*] $childrenTerm)

macro_rules
  | `(leanrx_jsx_logical% $element:leanrxJsxElement) => do
      match element with
      | `(leanrxJsxElement| <region $_:ident />) =>
          Macro.throwErrorAt element
            "error[LRX-VIEW-025]: keyed region slots require the typed component view"
      | `(leanrxJsxElement| <$tag:ident $attrs:leanrxJsxAttr* >
            [$children:leanrxJsxChild,*]) =>
          logicalElement tag attrs children.getElems
      | `(leanrxJsxElement| <$tag:ident $attrs:leanrxJsxAttr* />) =>
          logicalElement tag attrs #[]
      | _ => Macro.throwErrorAt element "error[LRX-VIEW-009]: malformed LeanRx JSX element"

macro_rules
  | `(leanrx_jsx_logical_keyed% for $binder:ident in $items:term key $keyValue:term =>
        $element:leanrxJsxElement) =>
      `(($items).map fun $binder =>
        LeanRx.Region.KeyedItem.mk $keyValue (leanrx_jsx_logical% $element))

/-- `jsx%` selects its lowering from the expected type: `Region.LogicalNode`
targets the logical reference model; anything else targets the schema-typed
safe view. -/
@[term_elab leanrxJsxTerm] private def elabLeanrxJsx : TermElab := fun stx expectedType? => do
  tryPostponeIfNoneOrMVar expectedType?
  let element : TSyntax `leanrxJsxElement := ⟨stx[1]⟩
  let logical ← match expectedType? with
    | some expected =>
        pure ((← whnf (← instantiateMVars expected)).isAppOf ``LeanRx.Region.LogicalNode)
    | none => pure false
  let lowered ←
    if logical then `(leanrx_jsx_logical% $element) else `(leanrx_jsx_typed% $element)
  elabTerm lowered expectedType?

/-- Top-level keyed `jsx%` produces the keyed region rows (`List KeyedItem`). -/
@[term_elab leanrxJsxKeyedTerm] private def elabLeanrxJsxKeyed : TermElab :=
    fun stx expectedType? => do
  let keyed : TSyntax `leanrxJsxKeyed := ⟨stx[1]⟩
  elabTerm (← `(leanrx_jsx_logical_keyed% $keyed)) expectedType?

end LeanRxDsl
