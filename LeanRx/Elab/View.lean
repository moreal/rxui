import LeanRx.View.Model
import LeanRx.Region.Keyed
import LeanRx.Component.Model
import LeanRx.Component.Dependent
import Lean.Elab.Macro
import Lean.Elab.Term
import Lean.Elab.SyntheticMVars

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

declare_syntax_cat leanrxJsxChild
declare_syntax_cat leanrxJsxElement
declare_syntax_cat leanrxJsxKeyed
scoped syntax str : leanrxJsxChild
scoped syntax "{" str ":" term "}" : leanrxJsxChild
scoped syntax "{" term "}" : leanrxJsxChild
scoped syntax leanrxJsxElement : leanrxJsxChild
scoped syntax "for " ident " in " term " key " term " => " leanrxJsxElement : leanrxJsxKeyed
scoped syntax leanrxJsxKeyed : leanrxJsxChild
scoped syntax "<" ident leanrxJsxAttr* ">" "[" leanrxJsxChild,* "]" : leanrxJsxElement
scoped syntax "<" ident leanrxJsxAttr* "/>" : leanrxJsxElement

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
  | `(leanrx_jsx_tag% ul) => `(LeanRx.HtmlTag.ul)
  | `(leanrx_jsx_tag% li) => `(LeanRx.HtmlTag.li)
  | `(leanrx_jsx_tag% input) => `(LeanRx.HtmlTag.input)
  | `(leanrx_jsx_tag% label) => `(LeanRx.HtmlTag.label)
  | `(leanrx_jsx_tag% strong) => `(LeanRx.HtmlTag.strong)
  | `(leanrx_jsx_tag% em) => `(LeanRx.HtmlTag.em)
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
private def componentHead? (tag : TSyntax `ident) : Bool :=
  match tag.getId.eraseMacroScopes with
  | .str _ shortName => shortName.length > 0 && shortName.front.isUpper
  | _ => false

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

private def typedElement (tag : TSyntax `ident) (attrs : Array Syntax)
    (children : Array Syntax) (span : Syntax) : MacroM (TSyntax `term) := do
  if componentHead? tag then
    componentCall tag attrs
  else do
    let attrTerms ← attrs.mapM fun attr =>
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
      | `(leanrxJsxAttr| class = { $_:term }) =>
          Macro.throwErrorAt attr
            "error[LRX-VIEW-012]: dynamic attribute values require the logical reference view"
      | `(leanrxJsxAttr| type = { $_:term }) =>
          Macro.throwErrorAt attr
            "error[LRX-VIEW-012]: dynamic attribute values require the logical reference view"
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
      | `(leanrxJsxChild| { $_:term }) =>
          Macro.throwErrorAt child
            "error[LRX-VIEW-012]: unnamed dynamic text requires the logical reference view"
      | `(leanrxJsxChild| $_:leanrxJsxKeyed) =>
          Macro.throwErrorAt child
            "error[LRX-VIEW-011]: keyed list children require the logical reference view"
      | `(leanrxJsxChild| $nested:leanrxJsxElement) => `(leanrx_jsx_typed% $nested)
      | _ => Macro.throwErrorAt child "error[LRX-VIEW-009]: malformed LeanRx JSX child"
    let spanTerm ← spanSyntax span
    `(LeanRx.View.nodeWith (leanrx_jsx_tag% $tag) [$childTerms,*]
      (attrs := [$attrTerms,*]) (span := $spanTerm))

macro_rules
  | `(leanrx_jsx_typed% $element:leanrxJsxElement) => do
      match element with
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
  | `(leanrxJsxAttr| onChange = $_:str) | `(leanrxJsxAttr| onChange = { $_:term }) =>
      Macro.throwErrorAt attr
        "error[LRX-VIEW-013]: event bindings are not representable in the logical reference view"
  | `(leanrxJsxAttr| $name:ident = $value:str) => do
      let mapped := Syntax.mkStrLit (← logicalAttrName name)
      `(($mapped, $value))
  | `(leanrxJsxAttr| $name:ident = { $value:term }) => do
      let mapped := Syntax.mkStrLit (← logicalAttrName name)
      `(($mapped, ($value : String)))
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
    componentCall tag attrs
  else do
    let attrTerms ← attrs.mapM logicalAttr
    let childrenTerm ← logicalChildren children
    `(LeanRx.Region.LogicalNode.element
      (LeanRx.HtmlTag.name (leanrx_jsx_tag% $tag)) [$attrTerms,*] $childrenTerm)

macro_rules
  | `(leanrx_jsx_logical% $element:leanrxJsxElement) => do
      match element with
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
