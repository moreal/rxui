import LeanRx
import examples.Counter

namespace LeanRxExamples.LeanRxDocs

open LeanRx LeanRxExamples.Counter

abbrev DocsSchema : Schema :=
  .field "page" Int <| .field "title" String <|
    .field "body" String <| .field "detail" String .empty

def page : Field DocsSchema Int := .here
def titleField : Field DocsSchema String := .there .here
def bodyField : Field DocsSchema String := .there (.there .here)
def detailField : Field DocsSchema String := .there (.there (.there .here))

open scoped LeanRxDsl in
/-- Staged with `rx%`; each tree matches the former hand-written constructor form. -/
private def isPage (index : Int) := rx% page == index

open scoped LeanRxDsl in
private def choosePage (introduction counter graph tabs effects limitations viewer : String) :=
  rx% if isPage 0 then introduction else
    if isPage 1 then counter else
    if isPage 2 then graph else
    if isPage 3 then tabs else
    if isPage 4 then effects else
    if isPage 5 then limitations else viewer

def counterGraphDot : String :=
  match CounterSyntax_check with
  | .ok checked => checked.graph.toDot
  | .error error => error.render

def title := choosePage
  "Introduction"
  "Counter"
  "Static graph"
  "Dependent Tabs"
  "Effects and resources"
  "Limitations"
  "Generated graph viewer"

def body := choosePage
  "LeanRx is a Lean-hosted frontend compiler experiment. Typed staged expressions carry complete static dependency sets into a certified graph and a controlled JavaScript backend."
  "Counter declares one Int source, two derived values, four events, and direct text sinks. Transactions batch nested writes, equality stops unchanged propagation, and no runtime observer discovers dependencies."
  "A checked component produces stable node IDs, direct dependencies, lawful equality plans, ranks, source spans, and a certified topological schedule. JSON, DOT, and script-free HTML artifacts are deterministic."
  "Dependent Tabs carries equal nonempty Vector lengths, stores selection as Fin, lowers one checked array access, erases proofs, and exports only finite private handlers plus mount."
  "Owned commands make timers, storage, HTTP, and foreign ports explicit. Replacement and disposal cancel exact handles; stale results cannot overwrite newer resource state."
  "The safe view is intentionally small. There is no URL router, general Virtual DOM, arbitrary Lean transpiler, raw HTML, URL attribute, CSS DSL, SSR, hydration, or formal proof of the JavaScript/DOM connection. Hostile text such as <img src=x onerror=\"globalThis.leanrxDocsXss=true\"> stays text."
  ("This page displays the public Counter graph artifact as inert text. The build also emits an accessible standalone LeanRxDocs.graph.html viewer.\n\n" ++ counterGraphDot)

def detail := choosePage
  "Start with the language guide, then run leanrx doctor and scaffold."
  "Use the public component API or the scoped component/JSX surface; generated *_schema, *_declarations, *_spec, and *_check names remain inspectable."
  "Formal graph claims cover dependency-indexed expressions and the abstract semantics subset. Generated HTML is a viewer, not a proof of browser behavior."
  "The runtime manifest records Vector/Fin representations while proof-erasure validation rejects surviving proof inspection in the controlled IR."
  "JavaScript promises, platform storage/network behavior, decoders, DOM delivery, and cancellation callbacks remain in the documented trusted computing base."
  "This documentation app uses state-driven native buttons instead of hiding the missing URL/history router behind another framework."
  "Open the standalone HTML graph artifact for card-based node metadata and the certified schedule."

open scoped LeanRxDsl in
private def selectPage (name : String) (index : Int) : EventSpec DocsSchema :=
  { name, update := .set page (rx% index) }

def showIntroduction := selectPage "showIntroduction" 0
def showCounter := selectPage "showCounter" 1
def showGraph := selectPage "showGraph" 2
def showTabs := selectPage "showTabs" 3
def showEffects := selectPage "showEffects" 4
def showLimitations := selectPage "showLimitations" 5
def showViewer := selectPage "showViewer" 6

private def navigationButton (label eventName : String) : View DocsSchema :=
  View.node .button [.text label]
    (attrs := [.buttonType .button])
    (events := [{ kind := .click, eventName }])

def docsView : View DocsSchema := View.node .main [
  View.node .h1 [.scalarText "pageTitle" (RxExpr.read titleField)],
  View.node .div [
    navigationButton "Introduction" "showIntroduction",
    navigationButton "Counter" "showCounter",
    navigationButton "Static graph" "showGraph",
    navigationButton "Dependent Tabs" "showTabs",
    navigationButton "Effects and resources" "showEffects",
    navigationButton "Limitations" "showLimitations",
    navigationButton "Generated graph viewer" "showViewer"
  ] (attrs := [.className "docs-navigation"]),
  View.node .p [.scalarText "pageBody" (RxExpr.read bodyField)]
    (attrs := [.className "docs-body"]),
  View.node .p [.scalarText "pageDetail" (RxExpr.read detailField)]
    (attrs := [.className "docs-detail"])
] (attrs := [.className "leanrx-docs"])

def spec : ComponentSpec DocsSchema :=
  { name := "LeanRxDocs"
    values := #[
      ValueSpec.state page (.int 0),
      ValueSpec.computed titleField title,
      ValueSpec.computed bodyField body,
      ValueSpec.computed detailField detail
    ]
    events := #[showIntroduction, showCounter, showGraph, showTabs, showEffects,
      showLimitations, showViewer]
    view := docsView }

open scoped LeanRxDsl

component LeanRxDocsSyntax (schema := DocsSchema) where {
  state page := ValueSpec.state page (.int 0);
  derived title := ValueSpec.computed titleField title;
  derived body := ValueSpec.computed bodyField body;
  derived detail := ValueSpec.computed detailField detail;
  event showIntroduction := showIntroduction;
  event showCounter := showCounter;
  event showGraph := showGraph;
  event showTabs := showTabs;
  event showEffects := showEffects;
  event showLimitations := showLimitations;
  event showViewer := showViewer;
  view := docsView;
}

end LeanRxExamples.LeanRxDocs
