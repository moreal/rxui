import examples.LeanRxDocsBuild

namespace LeanRxTest.Component.DocsSite

open LeanRx LeanRxExamples.LeanRxDocs

mutual
  private def countTag (expected : HtmlTag) : MountNode → Nat
    | .element tag _ children => (if tag == expected then 1 else 0) + countChildren expected children
    | .text _ | .dynamicText | .child .. | .region .. | .countText .. | .propText .. => 0

  private def countChildren (expected : HtmlTag) : MountChildren → Nat
    | .nil => 0
    | .cons head tail => countTag expected head + countChildren expected tail
end

def run : IO Unit := do
  unless pages.length == 11 && pages.map (·.slug) ==
      ["getting-started", "philosophy", "architecture", "components", "language", "tooling",
        "integrations", "accessibility", "backend-support", "trust-model",
        "dogfood-case-studies"] do
    throw <| IO.userError "documentation navigation order changed"
  let accepts (raw : String) := match SafeHref.parse raw with
    | .ok _ => true
    | .error _ => false
  unless accepts "https://example.com" && accepts "./docs/guides/components.md" &&
      !accepts "javascript:alert(1)" && !accepts "//example.com" do
    throw <| IO.userError "Markdown links escaped the safe URL boundary"
  match Docs.Markdown.render (Γ := DocsSchema) "<script>alert(1)</script>" with
  | .error error => throw <| IO.userError s!"raw HTML was not safely text-parsed: {error.render}"
  | .ok _ => pure ()
  match Docs.Markdown.render (Γ := DocsSchema) "![alt](image.png)" with
  | .error error =>
      unless error.code == "LRX-DOC-002" do
        throw <| IO.userError "unsupported Markdown lost its stable diagnostic"
  | .ok _ => throw <| IO.userError "unsupported Markdown image was silently accepted"
  LeanRxExamples.LeanRxDocsBuild.withChecked fun checked => do
    unless checked.sourceCount == 1 && checked.spec.values.size == 1 &&
        checked.spec.events.size == 11 && checked.view.textSinks.isEmpty &&
        checked.view.attrSelects.length == 33 && checked.graph.graph.nodes.size == 34 do
      throw <| IO.userError "MD4Lean documentation component shape changed"
    unless countTag .h1 checked.view.template == 11 &&
        countTag .table checked.view.template > 0 &&
        countTag .a checked.view.template > 0 &&
        countTag .pre checked.view.template > 0 do
      throw <| IO.userError "rendered Markdown lost headings, tables, links, or code blocks"
    let html := checked.graph.toHtml
    unless html.startsWith "<!doctype html>" && html.contains "Certified schedule" &&
        html.contains "n33 · attr:32:class" && ¬html.contains "<script" do
      throw <| IO.userError "documentation graph HTML lost accessibility or text safety"

end LeanRxTest.Component.DocsSite
