import LeanRx.View.Model
import Lean.Elab.Macro

open Lean Macro

namespace LeanRxDsl

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
          let attrTerms ← attrs.mapM fun attr => `(leanrx_jsx_attr% $attr)
          let childTerms ← children.getElems.mapM fun child => `(leanrx_jsx_child% $child)
          `(LeanRx.View.nodeWith (leanrx_jsx_tag% $tag) [$childTerms,*] [$attrTerms,*])
      | _ => Macro.throwErrorAt element "error[LRX-VIEW-009]: malformed LeanRx JSX element"

end LeanRxDsl
