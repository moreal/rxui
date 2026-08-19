import LeanRx.View.Model
import Lean.Elab.Macro
import Lean.Elab.Term

open Lean Elab Macro Term

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

declare_syntax_cat leanrxJsxAttr
scoped syntax "class" "=" str : leanrxJsxAttr
scoped syntax "id" "=" str : leanrxJsxAttr
scoped syntax "ariaLabel" "=" str : leanrxJsxAttr
scoped syntax "type" "=" str : leanrxJsxAttr
scoped syntax "onClick" "=" str : leanrxJsxAttr
scoped syntax ident "=" str : leanrxJsxAttr

declare_syntax_cat leanrxJsxChild
declare_syntax_cat leanrxJsxElement
scoped syntax str : leanrxJsxChild
scoped syntax "{" str ":" term "}" : leanrxJsxChild
scoped syntax leanrxJsxElement : leanrxJsxChild
scoped syntax "<" ident leanrxJsxAttr* ">" "[" leanrxJsxChild,* "]" : leanrxJsxElement

open scoped LeanRxDsl

syntax "leanrx_jsx_tag% " ident : term
macro_rules
  | `(leanrx_jsx_tag% main) => `(LeanRx.HtmlTag.main)
  | `(leanrx_jsx_tag% div) => `(LeanRx.HtmlTag.div)
  | `(leanrx_jsx_tag% button) => `(LeanRx.HtmlTag.button)
  | `(leanrx_jsx_tag% p) => `(LeanRx.HtmlTag.p)
  | `(leanrx_jsx_tag% span) => `(LeanRx.HtmlTag.span)
  | `(leanrx_jsx_tag% h1) => `(LeanRx.HtmlTag.h1)
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
  | `(leanrx_jsx_attr% rawHtml = $_:str) =>
      Macro.throwError "error[LRX-VIEW-010]: raw HTML is excluded from the safe view DSL"
  | `(leanrx_jsx_attr% $name:ident = $_:str) =>
      Macro.throwErrorAt name s!"error[LRX-VIEW-008]: unknown or invalid view attribute {name.getId}"

scoped syntax "jsx% " leanrxJsxElement : term
syntax "leanrx_jsx_child% " leanrxJsxChild : term

macro_rules
  | `(leanrx_jsx_child% $value:str) => `(LeanRx.View.text $value)
  | `(leanrx_jsx_child% { $name:str : $value:term }) =>
      `(LeanRx.View.scalarText $name $value)
  | `(leanrx_jsx_child% $element:leanrxJsxElement) => `(jsx% $element)

macro_rules
  | `(jsx% $element:leanrxJsxElement) => do
      match element with
      | `(leanrxJsxElement| <$tag:ident $attrs:leanrxJsxAttr* >
            [$children:leanrxJsxChild,*]) =>
          let attrTerms ← attrs.mapM fun attr =>
            let attrSyntax : TSyntax `leanrxJsxAttr := ⟨attr⟩
            match attrSyntax with
            | `(leanrxJsxAttr| onClick = $event:str) => do
                let span ← spanSyntax attr
                `(LeanRx.ViewAttr.event {
                  kind := LeanRx.EventKind.click, eventName := $event, span := $span
                })
            | _ => `(leanrx_jsx_attr% $attrSyntax)
          let childTerms ← children.getElems.mapM fun child =>
            match child with
            | `(leanrxJsxChild| $value:str) => do
                let span ← spanSyntax child
                `(LeanRx.View.text $value $span)
            | `(leanrxJsxChild| { $name:str : $value:term }) => do
                let span ← spanSyntax child
                `(LeanRx.View.scalarText $name $value $span)
            | `(leanrxJsxChild| $nested:leanrxJsxElement) => `(jsx% $nested)
            | _ => Macro.throwErrorAt child "error[LRX-VIEW-009]: malformed LeanRx JSX child"
          let span ← spanSyntax element
          `(LeanRx.View.nodeWith (leanrx_jsx_tag% $tag) [$childTerms,*]
            (attrs := [$attrTerms,*]) (span := $span))
      | _ => Macro.throwErrorAt element "error[LRX-VIEW-009]: malformed LeanRx JSX element"

end LeanRxDsl
