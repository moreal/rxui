import examples.LeanRxDocs

namespace LeanRxTest.Component.DocsSite

open LeanRx LeanRxExamples.LeanRxDocs

private def docsStore (slug : String) : Store DocsSchema :=
  .cons slug <| .cons "" <| .cons "" <| .cons "" <| .cons "" <| .cons "" <|
    .cons "" .empty

private def assertPage (slug expectedTitle needle : String) : IO Unit := do
  let store := docsStore slug
  unless title.eval store == expectedTitle && (body.eval store).contains needle do
    throw <| IO.userError s!"documentation page {slug} changed"

def run : IO Unit := do
  for expression in [eyebrow, title, lead, body, sample, note] do
    unless expression.dependencies.ids == [0] do
      throw <| IO.userError "documentation pages lost their static source dependency"
  assertPage "getting-started" "Build a checked browser component" "Run doctor"
  assertPage "philosophy" "Make frontend behavior inspectable" "Static dependency sets"
  assertPage "reactivity" "Dependencies are data, not runtime guesses" "affected frontier"
  assertPage "components" "Write a small staged component" "safe view"
  assertPage "tailwind" "Tailwind works as a build-time compiler" "@tailwindcss/cli 4.3.3"
  assertPage "ui" "A small Lean-native kit, not shadcn/ui" "not directly consumable"
  assertPage "limitations" "Know what LeanRx cannot do yet" "no general URL router"
  unless pages.map (·.slug) ==
      ["getting-started", "philosophy", "reactivity", "components", "tailwind", "ui",
        "limitations"] do
    throw <| IO.userError "documentation navigation order changed"
  let uiButton := (UI.button (Γ := DocsSchema) "Continue" "continue" .outline).split
  match uiButton.template with
  | .element .button attrs _ =>
      unless attrs.any (fun attr => attr.name == "class" && attr.value.contains "min-h-11") &&
          attrs.contains (.buttonType .button) &&
          uiButton.events.map (·.binding.eventName) == ["continue"] do
        throw <| IO.userError "source-owned UI button lost native semantics"
  | _ => throw <| IO.userError "source-owned UI button stopped mounting a native button"
  match LeanRxDocsSyntax_check with
  | .error error => throw <| IO.userError s!"docs component rejected: {error.render}"
  | .ok checked =>
      unless checked.sourceCount == 1 && checked.spec.values.size == 7 &&
          checked.spec.events.size == 7 && checked.view.textSinks.length == 6 &&
          checked.view.attrSelects.length == 14 && checked.graph.graph.nodes.size == 27 &&
          (checked.graph.graph.nodes.map (·.name) |>.take 13) ==
            #["page", "eyebrow", "title", "lead", "body", "sample", "note",
              "pageEyebrow", "pageTitle", "pageLead", "pageBody", "pageSample", "pageNote"] do
        throw <| IO.userError "documentation framework component shape changed"
      let html := checked.graph.toHtml
      unless html.startsWith "<!doctype html>" && html.contains "Certified schedule" &&
          html.contains "&lt;main&gt;" && ¬html.contains "<script" do
        throw <| IO.userError "documentation graph HTML lost accessibility or text safety"

end LeanRxTest.Component.DocsSite
