import examples.LeanRxDocs
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.LeanRxDocsBuild

open LeanRx LeanRxExamples.LeanRxDocs

def generatedDeclarationsSource : String := String.intercalate "\n" [
  "import examples.LeanRxDocs",
  "",
  "namespace LeanRxGenerated.Docs",
  "",
  "abbrev Schema := LeanRxExamples.LeanRxDocs.LeanRxDocsSyntax_schema",
  "def declarations := LeanRxExamples.LeanRxDocs.LeanRxDocsSyntax_declarations",
  "abbrev Spec := LeanRxExamples.LeanRxDocs.LeanRxDocsSyntax_spec",
  "abbrev Check := LeanRxExamples.LeanRxDocs.LeanRxDocsSyntax_check",
  "",
  "end LeanRxGenerated.Docs",
  ""
]

private def indexHtml : String := String.intercalate "\n" [
  "<!doctype html>",
  "<html lang=\"en\">",
  "<head>",
  "  <meta charset=\"utf-8\">",
  "  <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">",
  "  <title>LeanRx documentation</title>",
  "  <link rel=\"stylesheet\" href=\"./styles.css\">",
  "</head>",
  "<body>",
  "  <div id=\"app\"></div>",
  "  <script type=\"module\">",
  "    import { mount } from \"./LeanRxDocs.mjs\";",
  "    globalThis.leanrxDocsDispose = mount(document.getElementById(\"app\"));",
  "  </script>",
  "</body>",
  "</html>",
  ""
]

private def styles : String := String.intercalate "\n" [
  ":root { color-scheme: light dark; font-family: system-ui, sans-serif; }",
  "body { margin: 0; }",
  ".leanrx-docs { max-width: 72rem; margin: auto; padding: 2rem; }",
  ".docs-navigation { display: flex; flex-wrap: wrap; gap: .5rem; margin-bottom: 2rem; }",
  ".docs-navigation button { min-height: 2.75rem; padding: .5rem .75rem; }",
  ".docs-body, .docs-detail { line-height: 1.6; white-space: pre-wrap; }",
  ".docs-detail { border-inline-start: .25rem solid currentColor; padding-inline-start: 1rem; }",
  "@media (max-width: 40rem) { .leanrx-docs { padding: 1rem; } }",
  ""
]

private def generateChecked (directory : System.FilePath)
    (checked : CheckedComponent DocsSchema) : IO Unit := do
  let emitted ← match Backend.Component.emit "LeanRxDocs.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"docs backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"docs printer failed: {error.code}"
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "LeanRxDocs.mjs") source
  IO.FS.writeFile (directory / "LeanRxDocs.mjs.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / "LeanRxDocs.graph.json") (checked.graph.toJson ++ "\n")
  IO.FS.writeFile (directory / "LeanRxDocs.graph.dot") (checked.graph.toDot ++ "\n")
  IO.FS.writeFile (directory / "LeanRxDocs.graph.html") (checked.graph.toHtml ++ "\n")
  IO.FS.writeFile (directory / "LeanRxDocs.generated.lean") generatedDeclarationsSource
  IO.FS.writeFile (directory / "index.html") indexHtml
  IO.FS.writeFile (directory / "styles.css") styles
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")
  IO.FS.writeFile (directory / "leanrx_host.mjs") (← IO.FS.readFile "runtime/leanrx_host.mjs")

def generateInto (directory : System.FilePath) : IO Unit :=
  match LeanRxDocsSyntax_spec.check with
  | .error error => throw <| IO.userError s!"docs component invalid: {error.render}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.LeanRxDocsBuild
