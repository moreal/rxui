import examples.IssueBrowser
import LeanRx.Cli.AtomicOutput

namespace LeanRxExamples.IssueBrowserBuild

open LeanRx LeanRx.Effect LeanRx.IssueBrowser LeanRxExamples.IssueBrowser

private def fixtureBody : String :=
  "{\"issues\":[{\"id\":1,\"title\":\"<img src=x onerror=\\\"globalThis.issueXss=true\\\">\"}],\"hasMore\":true}"

private def expectedJson : Except String String := do
  let transition := update initial .search
  let (handle, request, onResult) ← match transition.command with
    | .batch #[.none, .http handle request onResult] => .ok (handle, request, onResult)
    | _ => .error "Issue Browser search did not produce the initial HTTP command"
  let (query, page) ← match request.query with
    | #[("q", query), ("page", page)] => .ok (query, page)
    | _ => .error "Issue Browser HTTP query shape drifted"
  let (key, decoded) ← match onResult (.ok { status := 200, body := fixtureBody }) with
    | .received key (.ok decoded) => .ok (key, decoded)
    | _ => .error "Issue Browser decoder callback rejected the native fixture"
  let issue ← match decoded.issues[0]? with
    | some issue => .ok issue
    | none => .error "Issue Browser native decoder produced no fixture issue"
  let loaded := update transition.state (.received key (.ok decoded))
  let failed := update transition.state <| onResult (.ok { status := 503, body := "{}" })
  pure <| "{\"url\":" ++ GraphSerialize.jsonString request.url ++
    ",\"query\":" ++ GraphSerialize.jsonString query ++
    ",\"page\":" ++ GraphSerialize.jsonString page ++
    ",\"handle\":" ++ GraphSerialize.jsonString handle.debug ++
    ",\"firstIssue\":{\"id\":" ++ toString issue.id ++
    ",\"title\":" ++ GraphSerialize.jsonString issue.title ++ "}" ++
    ",\"hasMore\":" ++ (if decoded.hasMore then "true" else "false") ++
    ",\"loadedStatus\":" ++ GraphSerialize.jsonString (statusText loaded.state) ++
    ",\"httpFailureStatus\":" ++ GraphSerialize.jsonString (statusText failed.state) ++ "}\n"

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
  IO.FS.writeFile (directory / "leanrx_form_events.mjs")
    (← IO.FS.readFile "runtime/leanrx_form_events.mjs")
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
