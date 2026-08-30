import LeanRx

namespace LeanRxExamples.LeanRxDocs

open LeanRx

abbrev DocsSchema : Schema :=
  .field "page" String <| .field "eyebrow" String <| .field "title" String <|
    .field "lead" String <| .field "body" String <| .field "sample" String <|
      .field "note" String .empty

def page : Field DocsSchema String := .here
def eyebrowField : Field DocsSchema String := .there .here
def titleField : Field DocsSchema String := .there (.there .here)
def leadField : Field DocsSchema String := .there (.there (.there .here))
def bodyField : Field DocsSchema String := .there (.there (.there (.there .here)))
def sampleField : Field DocsSchema String := .there (.there (.there (.there (.there .here))))
def noteField : Field DocsSchema String :=
  .there (.there (.there (.there (.there (.there .here)))))

def pages : List Docs.Page := [
  { slug := "getting-started", label := "Getting Started", eventName := "showGettingStarted" },
  { slug := "philosophy", label := "Philosophy", eventName := "showPhilosophy" },
  { slug := "reactivity", label := "How it works", eventName := "showReactivity" },
  { slug := "components", label := "Components", eventName := "showComponents" },
  { slug := "tailwind", label := "Tailwind", eventName := "showTailwind" },
  { slug := "ui", label := "UI primitives", eventName := "showUi" },
  { slug := "limitations", label := "Limits", eventName := "showLimitations" }
]

open scoped LeanRxDsl in
private def isPage (slug : String) := rx% page == slug

open scoped LeanRxDsl in
private def choosePage (gettingStarted philosophy reactivity components tailwind ui limitations :
    String) :=
  rx% if isPage "getting-started" then gettingStarted else
    if isPage "philosophy" then philosophy else
    if isPage "reactivity" then reactivity else
    if isPage "components" then components else
    if isPage "tailwind" then tailwind else
    if isPage "ui" then ui else limitations

def eyebrow := choosePage
  "START HERE"
  "DESIGN PRINCIPLES"
  "STATIC REACTIVITY"
  "AUTHORING"
  "STYLING INTEGRATION"
  "SOURCE-OWNED UI"
  "HONEST BOUNDARIES"

def title := choosePage
  "Build a checked browser component"
  "Make frontend behavior inspectable"
  "Dependencies are data, not runtime guesses"
  "Write a small staged component"
  "Tailwind works as a build-time compiler"
  "A small Lean-native kit, not shadcn/ui"
  "Know what LeanRx cannot do yet"

def lead := choosePage
  "Diagnose the toolchain, scaffold a public-API component, check it, and publish an atomic browser bundle."
  "LeanRx trades unrestricted host-language escape hatches for typed staged expressions, deterministic artifacts, and explicit trust boundaries."
  "Every source, derived value, and text sink enters a checked graph before JavaScript is emitted."
  "The component command keeps state, derived values, events, and the safe view in one inspectable declaration."
  "Lean source contains ordinary complete utility classes; Tailwind v4 scans those files and emits a zero-runtime stylesheet before publication."
  "LeanRx.UI provides the first button, callout, and code-block primitives as editable Lean source with closed semantic variants."
  "This dogfood is useful precisely because it records missing product capabilities instead of hiding them behind another framework."

def body := choosePage
  ("1. Run doctor to verify Lean, Node, pnpm, Tailwind, Playwright, Chromium, and the runtime ABI.\n" ++
   "2. Scaffold and type-check App.lean.\n" ++
   "3. Check the registered component and inspect its graph.\n" ++
   "4. Build a complete versioned bundle; the output path is an atomic managed pointer.")
  ("Lean is the host and proof language, not a promise to transpile arbitrary Lean. The browser " ++
   "surface is deliberately staged and closed. Static dependency sets drive both native reasoning " ++
   "and backend scheduling. Security, accessibility, performance, and remaining trust are contracts " ++
   "with executable gates rather than marketing adjectives.")
  ("A transaction batches source writes. The certified rank order evaluates only the affected " ++
   "frontier. Equality stops propagation when a derived value is unchanged, and sink caches avoid " ++
   "same-value DOM writes. No Proxy, observer stack, Virtual DOM diff, or runtime dependency " ++
   "discovery participates in this path.")
  ("State and derived expressions are typed against one schema. Events can only perform supported " ++
   "updates. The JSX-like surface lowers to a safe view whose tags, attributes, and event classes " ++
   "are closed enums. The generated schema, declarations, spec, check result, graph, manifest, and " ++
   "ES module remain inspectable.")
  ("The docs bundle runs @tailwindcss/cli 4.3.3 inside the atomic staging directory. Source " ++
   "detection is explicit, so class names in LeanRx.UI, LeanRx.Docs, and this component are included. " ++
   "CSS variables own light and dark theme values; LeanRx itself ships no CSS runtime.")
  ("The shadcn/ui CLI emits React or JavaScript components around React-oriented primitives and " ++
   "expects its own project configuration, so its components are not directly consumable by LeanRx. " ++
   "The transferable idea is source ownership: copy small Lean primitives, keep variants closed, and " ++
   "use native semantics. Dialogs, menus, popovers, focus traps, and an installable registry do not " ++
   "exist yet.")
  ("There is no general URL router, SSR, hydration, Markdown/MDX compiler, arbitrary HTML, URL " ++
   "attribute, JavaScript escape hatch, or released package contract. Documentation navigation is " ++
   "state-driven, and code copy is not wired because no clipboard capability exists. Generated " ++
   "JavaScript, the DOM, Tailwind, and platform behavior remain outside the formal proof boundary.")

def sample := choosePage
  ("lake exe leanrx -- doctor\n" ++
   "lake exe leanrx -- scaffold --out .tmp/starter\n" ++
   "lake env lean .tmp/starter/App.lean\n" ++
   "lake exe leanrx -- check Examples.Counter\n" ++
   "lake exe leanrx -- build Examples.Counter --out .tmp/counter")
  ("source → typed RxExpr → checked graph → Reactive IR\n" ++
   "       → validated JavaScript AST → direct DOM ESM\n\n" ++
   "proved subset ≠ browser trusted computing base")
  ("state count : Int := 0\n" ++
   "derived doubled := rx% count * 2\n" ++
   "event increment := set count (count + 1)\n" ++
   "view sink := rx% s!\"Count: {count}\"")
  ("open scoped LeanRxDsl\n\n" ++
   "component Counter (schema := CounterSchema) where {\n" ++
   "  state count : Int := 0;\n" ++
   "  derived label := rx% s!\"Count: {count}\";\n" ++
   "  event increment := set count (count + 1);\n" ++
   "  view := jsx% <main> [\n" ++
   "    <h1> [{\"label\": rx% label}],\n" ++
   "    <button type=\"button\" onClick={increment}> [\"Increment\"]\n" ++
   "  ];\n" ++
   "}")
  ("@import \"tailwindcss\" source(none);\n" ++
   "@source \"../LeanRx/UI/Primitives.lean\";\n" ++
   "@source \"../LeanRx/Docs/Framework.lean\";\n" ++
   "@source \"./LeanRxDocs.lean\";\n\n" ++
   "corepack pnpm exec tailwindcss -i examples/LeanRxDocs.css -o styles.css --minify")
  ("UI.button \"Continue\" \"continue\" .primary\n" ++
   "UI.callout \"Heads up\" (View.node .p [.text \"Typed and source-owned.\"])\n" ++
   "UI.codeBlock \"exampleSource\" sourceExpression")
  ("Use LeanRx today for controlled experiments and dogfoods, not as a drop-in Astro, React, or " ++
   "shadcn replacement. The support matrix is part of the API.")

def note := choosePage
  "The repository is unreleased and has no remote package URL or selected license. Start from this checkout."
  "Formal claims cover the pure Lean semantics subset. Emitted JavaScript and browser delivery are tested, not proved."
  "One page change in this site evaluates a known frontier; browser tests assert exact work and same-value suppression."
  "Unsupported tags, attributes, payloads, and staged terms are build errors. They never silently fall back to arbitrary JavaScript."
  "This is an actual Tailwind CLI build, not a CDN demo or a claim based only on compatible class strings."
  "Direct shadcn/ui compatibility: no. Tailwind styling and the source-owned component model: yes, with the tested primitives shown here."
  "The next usability milestones are a router, Markdown ingestion, clipboard and search capabilities, then a larger accessible primitive registry."

open scoped LeanRxDsl in
private def selectPage (name slug : String) : EventSpec DocsSchema :=
  { name, update := .set page (rx% slug) }

def showGettingStarted := selectPage "showGettingStarted" "getting-started"
def showPhilosophy := selectPage "showPhilosophy" "philosophy"
def showReactivity := selectPage "showReactivity" "reactivity"
def showComponents := selectPage "showComponents" "components"
def showTailwind := selectPage "showTailwind" "tailwind"
def showUi := selectPage "showUi" "ui"
def showLimitations := selectPage "showLimitations" "limitations"

def docsView : View DocsSchema :=
  Docs.shell page pages (RxExpr.read eyebrowField) (RxExpr.read titleField)
    (RxExpr.read leadField) (RxExpr.read bodyField) (RxExpr.read sampleField)
    (RxExpr.read noteField)

def spec : ComponentSpec DocsSchema :=
  { name := "LeanRxDocs"
    values := #[
      ValueSpec.state page (.string "getting-started"),
      ValueSpec.computed eyebrowField eyebrow,
      ValueSpec.computed titleField title,
      ValueSpec.computed leadField lead,
      ValueSpec.computed bodyField body,
      ValueSpec.computed sampleField sample,
      ValueSpec.computed noteField note
    ]
    events := #[showGettingStarted, showPhilosophy, showReactivity, showComponents,
      showTailwind, showUi, showLimitations]
    view := docsView }

open scoped LeanRxDsl

component LeanRxDocsSyntax (schema := DocsSchema) where {
  state page := ValueSpec.state page (.string "getting-started");
  derived eyebrow := ValueSpec.computed eyebrowField eyebrow;
  derived title := ValueSpec.computed titleField title;
  derived lead := ValueSpec.computed leadField lead;
  derived body := ValueSpec.computed bodyField body;
  derived sample := ValueSpec.computed sampleField sample;
  derived note := ValueSpec.computed noteField note;
  event showGettingStarted := showGettingStarted;
  event showPhilosophy := showPhilosophy;
  event showReactivity := showReactivity;
  event showComponents := showComponents;
  event showTailwind := showTailwind;
  event showUi := showUi;
  event showLimitations := showLimitations;
  view := docsView;
}

end LeanRxExamples.LeanRxDocs
