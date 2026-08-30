import LeanRx

namespace LeanRxExamples.LeanRxDocs

open LeanRx

abbrev DocsSchema : Schema := .field "page" String .empty

def page : Field DocsSchema String := .here

/-- A guide selected for the rendered documentation site. Keeping this list
explicit makes navigation and bundle inputs deterministic. -/
structure Guide where
  page : Docs.Page
  path : System.FilePath

def guides : List Guide := [
  { page := { slug := "getting-started", label := "Getting started", eventName := "showGettingStarted" },
    path := "docs/guides/getting-started.md" },
  { page := { slug := "philosophy", label := "Philosophy", eventName := "showPhilosophy" },
    path := "docs/guides/philosophy.md" },
  { page := { slug := "architecture", label := "Architecture", eventName := "showArchitecture" },
    path := "docs/guides/architecture.md" },
  { page := { slug := "components", label := "Components", eventName := "showComponents" },
    path := "docs/guides/components.md" },
  { page := { slug := "language", label := "Language", eventName := "showLanguage" },
    path := "docs/guides/language.md" },
  { page := { slug := "tooling", label := "Tooling", eventName := "showTooling" },
    path := "docs/guides/tooling.md" },
  { page := { slug := "integrations", label := "Integrations", eventName := "showIntegrations" },
    path := "docs/guides/integrations.md" },
  { page := { slug := "accessibility", label := "Accessibility", eventName := "showAccessibility" },
    path := "docs/guides/accessibility.md" },
  { page := { slug := "backend-support", label := "Backend support", eventName := "showBackendSupport" },
    path := "docs/guides/backend-support.md" },
  { page := { slug := "trust-model", label := "Trust model", eventName := "showTrustModel" },
    path := "docs/guides/trust-model.md" },
  { page := { slug := "dogfood-case-studies", label := "Case studies", eventName := "showCaseStudies" },
    path := "docs/guides/dogfood-case-studies.md" }
]

def pages : List Docs.Page := guides.map (·.page)

open scoped LeanRxDsl in
private def selectPage (metadata : Docs.Page) : EventSpec DocsSchema :=
  { name := metadata.eventName, update := .set page (rx% metadata.slug) }

/-- Build the checked component input from already parsed guide views. -/
def spec (rendered : List (Docs.RenderedPage DocsSchema)) : ComponentSpec DocsSchema :=
  { name := "LeanRxDocs"
    values := #[ValueSpec.state page (.string "getting-started")]
    events := (pages.map selectPage).toArray
    view := Docs.markdownShell page rendered }

end LeanRxExamples.LeanRxDocs
