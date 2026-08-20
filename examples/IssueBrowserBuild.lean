import examples.IssueBrowser
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.IssueBrowserBuild

open LeanRx LeanRx.Effect LeanRx.IssueBrowser LeanRxExamples.IssueBrowser

private def fixtureBody : String :=
  "{\"issues\":[{\"id\":1,\"title\":\"<img src=x onerror=\\\"globalThis.issueXss=true\\\">\"}],\"hasMore\":true}"

private def expectedJson : Except String String := do
  let transition := update initial .search
  let (handle, request) ← match transition.command with
    | .batch #[.none, .http handle request _] => .ok (handle, request)
    | _ => .error "Issue Browser search did not produce the initial HTTP command"
  let (query, page) ← match request.query with
    | #[("q", query), ("page", page)] => .ok (query, page)
    | _ => .error "Issue Browser HTTP query shape drifted"
  let decoded ← decodePage fixtureBody |>.mapError (fun error => error.message)
  let issue ← match decoded.issues[0]? with
    | some issue => .ok issue
    | none => .error "Issue Browser native decoder produced no fixture issue"
  pure <| "{\"url\":" ++ GraphSerialize.jsonString request.url ++
    ",\"query\":" ++ GraphSerialize.jsonString query ++
    ",\"page\":" ++ GraphSerialize.jsonString page ++
    ",\"handle\":" ++ GraphSerialize.jsonString handle.debug ++
    ",\"firstIssue\":{\"id\":" ++ toString issue.id ++
    ",\"title\":" ++ GraphSerialize.jsonString issue.title ++ "}" ++
    ",\"hasMore\":" ++ (if decoded.hasMore then "true" else "false") ++ "}\n"

private def generateChecked (directory : System.FilePath) (checked : Spec.Checked) : IO Unit := do
  let emitted ← match Backend.IssueBrowser.emit "IssueBrowser.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"Issue Browser backend failed: {error.code}"
  let source ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"Issue Browser printer failed: {error.code}"
  let expected ← match expectedJson with
    | .ok value => pure value
    | .error error => throw <| IO.userError error
  IO.FS.createDirAll directory
  IO.FS.writeFile (directory / "IssueBrowser.mjs") source
  IO.FS.writeFile (directory / "IssueBrowser.mjs.manifest.json") emitted.manifest.json
  IO.FS.writeFile (directory / "IssueBrowser.expected.json") expected
  IO.FS.writeFile (directory / "leanrx_dom.mjs") (← IO.FS.readFile "runtime/leanrx_dom.mjs")
  IO.FS.writeFile (directory / "leanrx_host.mjs") (← IO.FS.readFile "runtime/leanrx_host.mjs")
  IO.FS.writeFile (directory / "leanrx_region.mjs") (← IO.FS.readFile "runtime/leanrx_region.mjs")
  IO.FS.writeFile (directory / "leanrx_effects.mjs") (← IO.FS.readFile "runtime/leanrx_effects.mjs")
  IO.FS.writeFile (directory / "leanrx_issue_ports.mjs")
    (← IO.FS.readFile "runtime/leanrx_issue_ports.mjs")

def generateInto (directory : System.FilePath) : IO Unit :=
  match spec.check with
  | .error error => throw <| IO.userError s!"Issue Browser component invalid: {error.code}"
  | .ok checked => generateChecked directory checked

def generate (directory : System.FilePath) : IO Unit :=
  LeanRx.Cli.AtomicOutput.replaceDirectory directory generateInto

end LeanRxExamples.IssueBrowserBuild
