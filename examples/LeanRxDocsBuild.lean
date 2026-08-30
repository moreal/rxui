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
  "  <meta name=\"description\" content=\"Learn LeanRx through its self-hosted docs dogfood.\">",
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

private def rootMarkdownFiles : List String := [
  "ARCHITECTURE.md",
  "BENCHMARK.md",
  "DECISIONS.md",
  "DOGFOOD.md",
  "NOTICE.md",
  "PLAN.md",
  "README.md",
  "STATUS.md"
]

private def buildManifest : String := String.intercalate "\n" [
  "{",
  "  \"framework\": \"LeanRx.Docs\",",
  "  \"styling\": \"Tailwind CSS 4.3.3\",",
  "  \"ui\": \"LeanRx.UI experimental source primitives\",",
  "  \"shadcnDirectCompatibility\": false,",
  "  \"markdownExport\": true",
  "}",
  ""
]

private def compileTailwind (directory : System.FilePath) : IO Unit := do
  let input := directory / "LeanRxDocs.input.css"
  let output := directory / "styles.css"
  IO.FS.writeFile input (← IO.FS.readFile "examples/LeanRxDocs.css")
  let result ← IO.Process.output {
    cmd := "corepack"
    args := #["pnpm", "exec", "tailwindcss", "-i", "examples/LeanRxDocs.css",
      "-o", output.toString, "--minify"]
  }
  unless result.exitCode == 0 do
    throw <| IO.userError s!"Tailwind build failed: {result.stderr.trimAscii}"

private def copyMarkdownTree (source target : System.FilePath) : IO Unit := do
  let mut pending := #[(source, target)]
  let mut index := 0
  while index < pending.size do
    let (currentSource, currentTarget) := pending[index]!
    index := index + 1
    IO.FS.createDirAll currentTarget
    for entry in ← currentSource.readDir do
      match (← entry.path.symlinkMetadata).type with
      | .dir =>
          unless entry.fileName.contains ".leanrx-bundle-" do
            pending := pending.push (entry.path, currentTarget / entry.fileName)
      | .file =>
          if entry.fileName.endsWith ".md" then
            IO.FS.writeFile (currentTarget / entry.fileName) (← IO.FS.readFile entry.path)
      | _ => pure ()

private def copyMarkdownDocumentation (directory : System.FilePath) : IO Unit := do
  copyMarkdownTree "docs" (directory / "docs")
  for file in rootMarkdownFiles do
    IO.FS.writeFile (directory / file) (← IO.FS.readFile file)

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
  IO.FS.writeFile (directory / "leanrx-docs.json") buildManifest
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")
  copyMarkdownDocumentation directory
  compileTailwind directory

def generateInto (directory : System.FilePath) : IO Unit :=
  match LeanRxDocsSyntax_spec.check with
  | .error error => throw <| IO.userError s!"docs component invalid: {error.render}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.LeanRxDocsBuild
