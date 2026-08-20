import LeanRx.Effect.Resource

namespace LeanRxTest.Effect.Resource

open LeanRx.Effect

private def assertTrue (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  let first := Handle.first
  let second := first.next
  let loading : Resource String := .start second
  assertTrue (match loading.settle first (.ok "stale") with
    | .loading handle => handle == second
    | _ => false)
    "stale resource completion overwrote the active request"
  assertTrue (match loading.cancel first with
    | .loading handle => handle == second
    | _ => false)
    "stale resource cancellation changed the active request"
  assertTrue (match loading.settle second (.ok "fresh") with
    | .success handle value => handle == second && value == "fresh"
    | _ => false)
    "active resource success did not settle"
  let failure : Error := { code := "HTTP", message := "offline" }
  assertTrue (match loading.settle second (.error failure) with
    | .failure handle error => handle == second && error.code == "HTTP"
    | _ => false)
    "active resource failure did not settle"
  assertTrue (match loading.cancel second with
    | .cancelled handle => handle == second
    | _ => false)
    "active resource cancellation did not settle"

end LeanRxTest.Effect.Resource
