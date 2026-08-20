import examples.LeanRxDocs

namespace LeanRxTest.Component.DocsSite

open LeanRx LeanRxExamples.LeanRxDocs

private def docsStore (index : Int) : Store DocsSchema :=
  .cons index <| .cons "" <| .cons "" <| .cons "" .empty

private def assertPage (index : Int) (expectedTitle needle : String) : IO Unit := do
  let store := docsStore index
  unless title.eval store == expectedTitle && (body.eval store).contains needle do
    throw <| IO.userError s!"documentation page {index} changed"

def run : IO Unit := do
  unless title.dependencies.ids == [0] && body.dependencies.ids == [0] &&
      detail.dependencies.ids == [0] do
    throw <| IO.userError "documentation pages lost their static source dependency"
  assertPage 0 "Introduction" "Lean-hosted frontend compiler experiment"
  assertPage 1 "Counter" "one Int source"
  assertPage 2 "Static graph" "certified topological schedule"
  assertPage 3 "Dependent Tabs" "stores selection as Fin"
  assertPage 4 "Effects and resources" "Owned commands"
  assertPage 5 "Limitations" "no URL router"
  assertPage 6 "Generated graph viewer" "digraph LeanRx"
  match LeanRxDocsSyntax_check with
  | .error error => throw <| IO.userError s!"docs component rejected: {error.render}"
  | .ok checked =>
      unless checked.sourceCount == 1 && checked.spec.values.size == 4 &&
          checked.spec.events.size == 7 && checked.view.textSinks.length == 3 &&
          checked.graph.graph.nodes.map (·.name) ==
            #["page", "title", "body", "detail", "pageTitle", "pageBody", "pageDetail"] do
        throw <| IO.userError "documentation component shape changed"
      let html := checked.graph.toHtml
      unless html.startsWith "<!doctype html>" && html.contains "Certified schedule" &&
          html.contains "&lt;img" && ¬html.contains "<script" do
        throw <| IO.userError "documentation graph HTML lost accessibility or hostile-text safety"

end LeanRxTest.Component.DocsSite
