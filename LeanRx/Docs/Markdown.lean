import MD4Lean
import LeanRx.Docs.Framework

namespace LeanRx.Docs.Markdown

open LeanRx

/-- Stable failure returned while crossing from Markdown into the safe view. -/
structure Error where
  code : String
  message : String
deriving Repr, BEq

def Error.render (error : Error) : String := s!"error[{error.code}]: {error.message}"

private def unsupported (kind : String) : Except Error α :=
  throw { code := "LRX-DOC-002", message := s!"unsupported Markdown construct: {kind}" }

private def entityText : String → String
  | "&amp;" => "&"
  | "&lt;" => "<"
  | "&gt;" => ">"
  | "&quot;" => "\""
  | "&apos;" => "'"
  | value => value

private def attrText (values : Array MD4Lean.AttrText) : Except Error String := do
  let mut result := ""
  for value in values do
    match value with
    | .normal text => result := result ++ text
    | .entity text => result := result ++ entityText text
    | .nullchar => throw { code := "LRX-DOC-003", message := "null character in Markdown attribute" }
  pure result

private def linkHref (linkPrefix : String) (raw : String) : Except Error SafeHref := do
  let target :=
    if raw.startsWith "http://" || raw.startsWith "https://" || raw.startsWith "mailto:" ||
        raw.startsWith "#" || raw.startsWith "/" then raw
    else linkPrefix ++ raw
  match SafeHref.parse target with
  | .ok href => pure href
  | .error reason =>
      throw { code := "LRX-DOC-004", message := s!"unsafe Markdown link `{raw}`: {reason}" }

mutual
  private def inlines (Γ : Schema) (linkPrefix : String) (values : Array MD4Lean.Text) :
      Except Error (List (View Γ)) := do
    let mut result := []
    for value in values do
      result := result ++ (← inline Γ linkPrefix value)
    pure result

  private def inline (Γ : Schema) (linkPrefix : String) :
      MD4Lean.Text → Except Error (List (View Γ))
    | .normal text => pure [.text text]
    | .nullchar => pure [.text "�"]
    | .br _ => pure [View.node .br []]
    | .softbr _ => pure [.text "\n"]
    | .entity text => pure [.text (entityText text)]
    | .em children => do pure [View.node .em (← inlines Γ linkPrefix children)]
    | .strong children => do pure [View.node .strong (← inlines Γ linkPrefix children)]
    | .a destination _title _isAuto children =>
        match attrText destination with
        | .error error => .error error
        | .ok raw => match linkHref linkPrefix raw with
          | .error error => .error error
          | .ok safeHref => match inlines Γ linkPrefix children with
            | .error error => .error error
            | .ok rendered => .ok [View.node .a rendered
                (attrs := [
                  .href safeHref,
                  .className
                    "font-medium text-primary underline decoration-primary/40 underline-offset-4"
                ])]
    | .code chunks =>
        pure [View.node .code [.text (String.join chunks.toList)]
          (attrs := [.className "rounded bg-muted px-1.5 py-0.5 font-mono text-sm"])]
    | .del children => do pure [View.node .del (← inlines Γ linkPrefix children)]
    | .u _ => unsupported "underline"
    | .img .. => unsupported "image"
    | .latexMath .. => unsupported "inline math"
    | .latexMathDisplay .. => unsupported "display math"
    | .wikiLink .. => unsupported "wiki link"

  private def listItem (Γ : Schema) (linkPrefix : String) (item : MD4Lean.Li MD4Lean.Block) :
      Except Error (View Γ) := do
    if item.isTask then unsupported "task list"
    let content ← item.contents.toList.mapM fun child =>
      match child with
      | .p text => do
          pure <| View.node .p (← inlines Γ linkPrefix text)
            (attrs := [.className "leading-7"])
      | _ => unsupported "nested block in list item"
    pure <| View.node .li content
      (attrs := [.className "pl-1"])

  private def tableCell (Γ : Schema) (linkPrefix : String) (tag : HtmlTag)
      (cell : Array MD4Lean.Text) :
      Except Error (View Γ) := do
    pure <| View.node tag (← inlines Γ linkPrefix cell)
      (attrs := [.className "border border-border px-3 py-2 text-left align-top"])

  private def block (Γ : Schema) (linkPrefix : String) :
      MD4Lean.Block → Except Error (View Γ)
    | .p content => do
        pure <| View.node .p (← inlines Γ linkPrefix content)
          (attrs := [.className "my-4 whitespace-pre-wrap leading-7 text-muted-foreground"])
    | .ul _tight _mark items => do
        pure <| View.node .ul (← items.toList.mapM (listItem Γ linkPrefix))
          (attrs := [.className "my-4 list-disc space-y-2 pl-6 text-muted-foreground"])
    | .ol _tight _start _mark items => do
        pure <| View.node .ol (← items.toList.mapM (listItem Γ linkPrefix))
          (attrs := [.className "my-4 list-decimal space-y-2 pl-6 text-muted-foreground"])
    | .hr => pure <| View.node .hr [] (attrs := [.className "my-8 border-border"])
    | .header level content => do
        let children ← inlines Γ linkPrefix content
        let classes := match level with
          | 1 => "mb-6 text-balance text-3xl font-bold tracking-tight text-foreground sm:text-4xl"
          | 2 => "mb-3 mt-10 text-2xl font-semibold tracking-tight text-foreground"
          | _ => "mb-2 mt-8 text-xl font-semibold tracking-tight text-foreground"
        let tag := match level with
          | 1 => HtmlTag.h1
          | 2 => .h2
          | 3 => .h3
          | 4 => .h4
          | 5 => .h5
          | _ => .h6
        pure <| View.node tag children (attrs := [.className classes])
    | .code _info _lang _fenceChar content =>
        pure <| View.node .pre [
          View.node .code [.text (String.join content.toList)]
        ] (attrs := [
          .className
            "my-5 overflow-x-auto rounded-xl border border-border bg-muted p-4 text-sm leading-6"
        ])
    | .html _ => unsupported "raw HTML"
    | .blockquote _ => unsupported "block quote"
    | .table head body => do
        let headerCells ← head.toList.mapM (tableCell Γ linkPrefix .th)
        let bodyRows ← body.toList.mapM fun row => do
          pure <| View.node .tr (← row.toList.mapM (tableCell Γ linkPrefix .td))
        pure <| View.node .div [
          View.node .table [
            View.node .thead [View.node .tr headerCells],
            View.node .tbody bodyRows
          ] (attrs := [.className "w-full border-collapse text-sm"])
        ] (attrs := [.className "my-5 overflow-x-auto"])

  private def blocks (Γ : Schema) (linkPrefix : String) (values : Array MD4Lean.Block) :
      Except Error (List (View Γ)) :=
    values.toList.mapM (block Γ linkPrefix)
end

/-- Parse GitHub-flavored Markdown with raw HTML disabled and lower it into
LeanRx's closed view vocabulary. `relativeLinkPrefix` relocates relative URLs
to the copied source tree in the published bundle. -/
def render (source : String) (relativeLinkPrefix := "") : Except Error (List (View Γ)) :=
  let flags := MD4Lean.MD_DIALECT_GITHUB ||| MD4Lean.MD_FLAG_NOHTML
  match MD4Lean.parse source flags with
  | some document => blocks Γ relativeLinkPrefix document.blocks
  | none => .error { code := "LRX-DOC-001", message := "MD4Lean could not parse the document" }

end LeanRx.Docs.Markdown
