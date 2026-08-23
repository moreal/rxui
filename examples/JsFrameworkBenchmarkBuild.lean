import examples.JsFrameworkBenchmark
import LeanRx.Backend.JsCompact
import LeanRx.Cli.AtomicOutput
import LeanRx.Graph.Serialize

namespace LeanRxExamples.JsFrameworkBenchmarkBuild

open LeanRx LeanRxExamples.JsFrameworkBenchmark

private def indexHtml (name : String) : String :=
  "<!DOCTYPE html>\n" ++
  "<html lang=\"en\">\n" ++
  "<head>\n" ++
  "  <meta charset=\"utf-8\">\n" ++
  "  <title>" ++ name ++ "</title>\n" ++
  "  <link href=\"/css/currentStyle.css\" rel=\"stylesheet\">\n" ++
  "</head>\n" ++
  "<body>\n" ++
  "<div id=\"main\">\n" ++
  "  <div class=\"container\">\n" ++
  "    <div class=\"jumbotron\">\n" ++
  "      <div class=\"row\">\n" ++
  "        <div class=\"col-md-6\"><h1>" ++ name ++ "</h1></div>\n" ++
  "        <div class=\"col-md-6\"><div class=\"row\">\n" ++
  "          <div class=\"col-sm-6 smallpad\"><button type=\"button\" " ++
    "class=\"btn btn-primary btn-block\" id=\"run\" data-lrx-action=\"run\">" ++
    "Create 1,000 rows</button></div>\n" ++
  "          <div class=\"col-sm-6 smallpad\"><button type=\"button\" " ++
    "class=\"btn btn-primary btn-block\" id=\"runlots\" data-lrx-action=\"runlots\">" ++
    "Create 10,000 rows</button></div>\n" ++
  "          <div class=\"col-sm-6 smallpad\"><button type=\"button\" " ++
    "class=\"btn btn-primary btn-block\" id=\"add\" data-lrx-action=\"add\">" ++
    "Append 1,000 rows</button></div>\n" ++
  "          <div class=\"col-sm-6 smallpad\"><button type=\"button\" " ++
    "class=\"btn btn-primary btn-block\" id=\"update\" data-lrx-action=\"update\">" ++
    "Update every 10th row</button></div>\n" ++
  "          <div class=\"col-sm-6 smallpad\"><button type=\"button\" " ++
    "class=\"btn btn-primary btn-block\" id=\"clear\" data-lrx-action=\"clear\">" ++
    "Clear</button></div>\n" ++
  "          <div class=\"col-sm-6 smallpad\"><button type=\"button\" " ++
    "class=\"btn btn-primary btn-block\" id=\"swaprows\" " ++
    "data-lrx-action=\"swaprows\">Swap Rows</button></div>\n" ++
  "        </div></div>\n" ++
  "      </div>\n" ++
  "    </div>\n" ++
  "    <table class=\"table table-hover table-striped test-data\">\n" ++
  "      <tbody id=\"tbody\"></tbody>\n" ++
  "    </table>\n" ++
  "    <span class=\"preloadicon glyphicon glyphicon-remove\" aria-hidden=\"true\"></span>\n" ++
  "  </div>\n" ++
  "</div>\n" ++
  "<script type=\"module\" src=\"./main.mjs\"></script>\n" ++
  "</body>\n" ++
  "</html>\n"

private def mainStatement : String :=
  "globalThis.leanrxBenchmarkDispose=mount(document.getElementById(\"main\"));\n"

-- Inlines one repository host into the flattened benchmark module (ADR-0023):
-- whole-line `//` comments, blank lines, and indentation are dropped and the
-- `export` keyword is removed from its function declarations; identifiers,
-- statements, and line order are kept. Hosts inlined this way must not contain
-- `import`/`export {` lines or multi-line string literals; the benchmark gate
-- syntax-checks and runs the result.
private def inlineHost (name : String) (source : String) : IO String := do
  let kept := (source.splitOn "\n").filterMap fun line =>
    let trimmed := line.trimAsciiStart.toString
    if trimmed.isEmpty || trimmed.startsWith "//" then none else some trimmed
  for line in kept do
    if line.startsWith "import " || line.startsWith "export {" || line.startsWith "export{" then
      throw <| IO.userError s!"JS framework benchmark host {name} cannot be inlined: {line}"
  pure <| String.join <| kept.map fun line =>
    (if line.startsWith "export " then (line.drop 7).toString else line) ++ "\n"

-- The generated module with its host imports resolved to the inlined host
-- declarations (free names) and no export list.
private def flattenedModule (module : Js.Module) : Js.Module :=
  { module with
    globals := module.globals ++ module.imports.flatMap fun entry => entry.names.map (·.2),
    imports := #[],
    exports := #[] }

private def packageJson : String :=
  "{\n" ++
  "  \"name\": \"js-framework-benchmark-leanrx\",\n" ++
  "  \"version\": \"0.1.0\",\n" ++
  "  \"private\": true,\n" ++
  "  \"type\": \"module\",\n" ++
  "  \"scripts\": {\n" ++
  "    \"build-prod\": \"exit 0\",\n" ++
  "    \"dev\": \"exit 0\"\n" ++
  "  },\n" ++
  "  \"js-framework-benchmark\": {\n" ++
  "    \"frameworkVersion\": " ++ GraphSerialize.jsonString LeanRx.version ++ ",\n" ++
  "    \"frameworkHomeURL\": \"https://github.com/moreal/rxui\",\n" ++
  "    \"language\": \"Lean 4 / JavaScript\"\n" ++
  "  },\n" ++
  "  \"license\": \"UNLICENSED\"\n" ++
  "}\n"

private def packageLock : String :=
  "{\n" ++
  "  \"name\": \"js-framework-benchmark-leanrx\",\n" ++
  "  \"version\": \"0.1.0\",\n" ++
  "  \"lockfileVersion\": 3,\n" ++
  "  \"requires\": true,\n" ++
  "  \"packages\": {\n" ++
  "    \"\": {\n" ++
  "      \"name\": \"js-framework-benchmark-leanrx\",\n" ++
  "      \"version\": \"0.1.0\",\n" ++
  "      \"license\": \"UNLICENSED\"\n" ++
  "    }\n" ++
  "  }\n" ++
  "}\n"

private def assetManifest : String :=
  "{\"files\":[\"index.html\",\"main.mjs\"]}\n"

private def generateChecked (directory : System.FilePath)
    (checked : LeanRx.JsFrameworkBenchmark.Spec.Checked) : IO Unit := do
  let emitted ← match Backend.JsFrameworkBenchmark.emit "main.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"JS framework benchmark backend failed: {error.code}"
  let compact ← match Js.Printer.module .compact (flattenedModule emitted.module) with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"JS framework benchmark printer failed: {error.code}"
  -- The page fetches one module: the hosts the generated module imports, in
  -- import order, then the generated declarations, then the mount statement.
  let mut hosts := ""
  for hostImport in emitted.manifest.hostImports do
    let name := (hostImport.splitOn "/").getLastD hostImport
    hosts := hosts ++ (← inlineHost name (← IO.FS.readFile ("runtime" / name)))
  -- ADR-0024: the flattened text is then compacted (whitespace, comments,
  -- short identifiers, dot member access); the compactor fails closed on any
  -- construct it does not model. ADR-0031: it first drops the inlined host
  -- declarations nothing reachable from the mount statement references.
  let main ← match Js.Compact.compact (hosts ++ compact ++ "\n" ++ mainStatement) (prune := true) with
    | .ok source => pure (source ++ "\n")
    | .error error =>
        throw <| IO.userError
          s!"JS framework benchmark compactor failed: {error.code}: {error.message}"
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "index.html") (indexHtml checked.spec.name)
  IO.FS.writeFile (directory / "main.mjs") main
  IO.FS.writeFile (directory / "main.mjs.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / "benchmark-assets.json") assetManifest
  IO.FS.writeFile (directory / "package.json") packageJson
  IO.FS.writeFile (directory / "package-lock.json") packageLock

def generateInto (directory : System.FilePath) : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"JS framework benchmark invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.JsFrameworkBenchmarkBuild
