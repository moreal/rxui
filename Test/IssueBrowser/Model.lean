import LeanRx.IssueBrowser.Model

namespace LeanRxTest.IssueBrowser.Model

open LeanRx.Effect LeanRx.IssueBrowser

private def assertTrue (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def page (id : Nat) (title : String) (hasMore : Bool) : Page := {
  issues := #[{ id, title }]
  hasMore
}

private def requestKey (transition : Transition) : Except String RequestKey :=
  match transition.command with
  | .batch #[_, .http _ _ onResult] =>
      match onResult (.ok { status := 200, body :=
          "{\"issues\":[{\"id\":9,\"title\":\"decoded\"}],\"hasMore\":false}" }) with
      | .received key (.ok decoded) =>
          if decoded.issues == #[{ id := 9, title := "decoded" }] then .ok key
          else .error "typed decoder returned the wrong issue"
      | _ => .error "HTTP callback did not produce a typed received message"
  | _ => .error "request transition did not return cancel-plus-http batch"

def run : IO Unit := do
  assertTrue (match decoderPort with
    | .ok port => port.name == "decodeIssueResponse" &&
        port.inputType == .record "HttpResponse" &&
        port.outputType == .record "IssuePage" &&
        port.errors == #["LRX-PORT-302", "LRX-PORT-303", "LRX-PORT-304"] &&
        (match port.runMock ⟨{ status := 200, body :=
            "{\"issues\":[{\"id\":4,\"title\":\"port\"}],\"hasMore\":false}" }⟩ with
        | .ok output => output.value.issues == #[{ id := 4, title := "port" }]
        | .error _ => false)
    | .error _ => false) "issue decoder foreign-port declaration drifted"
  assertTrue (match decodePage
      "{\"issues\":[{\"id\":1,\"title\":\"one\"}],\"hasMore\":true}" with
    | .ok decoded => decoded == { issues := #[{ id := 1, title := "one" }], hasMore := true }
    | .error _ => false)
    "valid issue JSON did not decode"
  assertTrue (match decodePage "{\"issues\":[{\"id\":\"bad\",\"title\":1}],\"hasMore\":false}" with
    | .error error => error.code == "LRX-PORT-302"
    | .ok _ => false) "invalid issue JSON was accepted"
  assertTrue (match decodePage
      "{\"issues\":[{\"id\":9007199254740991,\"title\":\"max\"}],\"hasMore\":false}" with
    | .ok page => page.issues[0]?.map (·.id) == some maxSafeIssueId
    | .error _ => false) "maximum safe issue ID was rejected"
  assertTrue (match decodePage
      "{\"issues\":[{\"id\":9007199254740992,\"title\":\"unsafe\"}],\"hasMore\":false}" with
    | .error error => error.code == "LRX-PORT-302"
    | .ok _ => false) "unsafe JavaScript issue ID was accepted natively"
  assertTrue (match decodePage
      "{\"issues\":[{\"id\":1e3,\"title\":\"exponent\"},{\"id\":-0,\"title\":\"zero\"}],\"hasMore\":false}" with
    | .ok page => page.issues.map (·.id) == #[1000, 0]
    | .error _ => false) "exact natural exponent or negative-zero issue ID was rejected"
  assertTrue (match decodePage
      "{\"issues\":[{\"id\":0e16,\"title\":\"bounded zero\"},{\"id\":1e15,\"title\":\"bounded value\"}],\"hasMore\":false}" with
    | .ok page => page.issues.map (·.id) == #[0, 1000000000000000]
    | .error _ => false) "bounded exact exponent issue IDs were rejected"
  for body in [
      "{\"issues\":[{\"id\":1.0,\"title\":\"decimal\"}],\"hasMore\":false}",
      "{\"issues\":[{\"id\":1.0000000000000001,\"title\":\"rounded\"}],\"hasMore\":false}",
      "{\"issues\":[{\"id\":9007199254740990.5,\"title\":\"rounded max\"}],\"hasMore\":false}",
      "{\"issues\":[{\"id\":0e9999999999999999999999999999999,\"title\":\"huge exponent\"}],\"hasMore\":false}",
      "{\"issues\":[{\"id\":-0e9999999999999999999999999999999,\"title\":\"negative zero exponent\"}],\"hasMore\":false}",
      "{\"issues\":[{\"id\":0e17,\"title\":\"exponent above bound\"}],\"hasMore\":false}",
      "{\"issues\":[{\"id\":0e-17,\"title\":\"negative exponent above bound\"}],\"hasMore\":false}"
    ] do
    assertTrue (match decodePage body with
      | .error error => error.code == "LRX-PORT-302"
      | .ok _ => false) s!"fractional issue ID was accepted natively: {body}"
  assertTrue (match decodePage
      "{\"issues\":[{\"id\":1,\"title\":\"a\"},{\"id\":1,\"title\":\"b\"}],\"hasMore\":false}" with
    | .error error => error.code == "LRX-PORT-304"
    | .ok _ => false) "duplicate issue IDs were accepted within one page"
  assertTrue (match decodeResponse (.ok { status := 503, body := "{}" }) with
    | .error error => error.code == "LRX-PORT-303"
    | .ok _ => false) "non-success HTTP status was accepted"
  assertTrue (match (Spec.create "").check with
    | .error error => error.code == "LRX-PORT-502"
    | .ok _ => false) "empty Issue Browser spec returned the wrong diagnostic"

  let first := update initial .search
  let firstKey ← match requestKey first with
    | .ok key => pure key
    | .error message => throw <| IO.userError message
  let second := update first.state (.setQuery "new & hostile")
  let secondKey ← match requestKey second with
    | .ok key => pure key
    | .error message => throw <| IO.userError message
  assertTrue (firstKey.handle != secondKey.handle)
    "query replacement reused the request handle"
  assertTrue (match second.command with
    | .batch #[.cancel cancelled, .http started request _] =>
        cancelled == firstKey.handle && started == secondKey.handle &&
          request.url == "/api/issues" &&
          request.query == #[("q", "new & hostile"), ("page", "1")]
    | _ => false) "query replacement did not cancel and safely structure the next request"

  let stale := update second.state (.received firstKey (.ok (page 1 "stale" false)))
  assertTrue (stale.state.issues.isEmpty)
    "stale response overwrote the newer query"
  let loaded := update second.state (.received secondKey (.ok (page 2 "fresh" true)))
  assertTrue (loaded.state.issues == #[{ id := 2, title := "fresh" }] &&
    loaded.state.currentPage == 1 && loaded.state.hasMore)
    "current response did not settle page one"
  let next := update loaded.state .nextPage
  let nextKey ← match requestKey next with
    | .ok key => pure key
    | .error message => throw <| IO.userError message
  let appended := update next.state (.received nextKey (.ok (page 3 "second page" false)))
  assertTrue (appended.state.issues == #[
    { id := 2, title := "fresh" }, { id := 3, title := "second page" }])
    "pagination replaced rather than appended issues"
  let duplicatePage := update next.state (.received nextKey (.ok (page 2 "duplicate" false)))
  assertTrue (duplicatePage.state.issues == loaded.state.issues &&
    statusText duplicatePage.state == "Request failed: issue response contains duplicate IDs")
    "cross-page duplicate key changed state or failed invisibly"

  let failing := update loaded.state .retry
  let failureKey ← match requestKey failing with
    | .ok key => pure key
    | .error message => throw <| IO.userError message
  let failed := update failing.state (.received failureKey (.error {
    code := "NETWORK", message := "offline"
  }))
  assertTrue (statusText failed.state == "Request failed: offline")
    "HTTP failure was not visible"
  let retried := update failed.state .retry
  assertTrue (match retried.command with
    | .batch #[.none, .http _ request _] => request.query.contains ("page", "1")
    | _ => false) "retry did not repeat the failed request"

  let disposed := update second.state .dispose
  assertTrue (disposed.state.disposed && match disposed.command with
    | .cancel handle => handle == secondKey.handle
    | _ => false) "disposal did not cancel the active HTTP request"
  let ignored := update disposed.state (.received secondKey (.ok (page 8 "late" false)))
  assertTrue (ignored.state.issues.isEmpty)
    "post-disposal HTTP result changed state"

end LeanRxTest.IssueBrowser.Model
