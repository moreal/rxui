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
  assertTrue (match decodePage
      "{\"issues\":[{\"id\":1,\"title\":\"one\"}],\"hasMore\":true}" with
    | .ok decoded => decoded == { issues := #[{ id := 1, title := "one" }], hasMore := true }
    | .error _ => false)
    "valid issue JSON did not decode"
  assertTrue (match decodePage "{\"issues\":[{\"id\":\"bad\",\"title\":1}],\"hasMore\":false}" with
    | .error error => error.code == "LRX-HTTP-DECODE-001"
    | .ok _ => false) "invalid issue JSON was accepted"
  assertTrue (match decodeResponse (.ok { status := 503, body := "{}" }) with
    | .error error => error.code == "LRX-HTTP-STATUS-001"
    | .ok _ => false) "non-success HTTP status was accepted"

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
