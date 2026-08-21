import examples.JsFrameworkBenchmark
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

private def mainModule : String :=
  "import { mount } from \"./LeanRx.mjs\";\n" ++
  "globalThis.leanrxBenchmarkDispose = mount(document.getElementById(\"main\"));\n"

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
  "{\"files\":[\"index.html\",\"main.mjs\",\"LeanRx.mjs\"," ++
  "\"leanrx_dom.mjs\",\"leanrx_region.mjs\",\"leanrx_host.mjs\"]}\n"

private def generateChecked (directory : System.FilePath)
    (checked : LeanRx.JsFrameworkBenchmark.Spec.Checked) : IO Unit := do
  let emitted ← match Backend.JsFrameworkBenchmark.emit "LeanRx.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"JS framework benchmark backend failed: {error.code}"
  let compact ← match Js.Printer.module .compact emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"JS framework benchmark printer failed: {error.code}"
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "index.html") (indexHtml checked.spec.name)
  IO.FS.writeFile (directory / "main.mjs") mainModule
  IO.FS.writeFile (directory / "LeanRx.mjs") (compact ++ "\n")
  IO.FS.writeFile (directory / "LeanRx.mjs.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / "benchmark-assets.json") assetManifest
  IO.FS.writeFile (directory / "package.json") packageJson
  IO.FS.writeFile (directory / "package-lock.json") packageLock
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")
  IO.FS.writeFile (directory / "leanrx_region.mjs") (← IO.FS.readFile "runtime/leanrx_region.mjs")
  IO.FS.writeFile (directory / "leanrx_host.mjs") (← IO.FS.readFile "runtime/leanrx_host.mjs")

def generateInto (directory : System.FilePath) : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"JS framework benchmark invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.JsFrameworkBenchmarkBuild
