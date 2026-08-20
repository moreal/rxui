import LeanRx.Notes.Model

namespace LeanRxTest.Notes.Model

open LeanRx.Effect LeanRx.Notes

private def assertTrue (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def isNone : Cmd Msg → Bool
  | .none => true
  | _ => false

def run : IO Unit := do
  let restore := update initial .restore
  let restoreHandle ← match restore.command with
    | .storageGet handle "leanrx.notes" _ => pure handle
    | _ => throw <| IO.userError "restore did not return typed storageGet"
  let restored := update restore.state (.restored restoreHandle (.ok (.found "native")))
  assertTrue (restored.state.text == "native") "restored note was not applied"

  let editedBeforeRestore := update restore.state (.edit "local wins")
  let staleRestore := update editedBeforeRestore.state
    (.restored restoreHandle (.ok (.found "stale storage")))
  assertTrue (staleRestore.state.text == "local wins")
    "late restore overwrote a newer local edit"

  let firstEdit := update restored.state (.edit "first")
  let firstHandle ← match pendingHandle firstEdit.state with
    | some handle => pure handle
    | none => throw <| IO.userError "first edit did not schedule persistence"
  let secondEdit := update firstEdit.state (.edit "second")
  let secondHandle ← match pendingHandle secondEdit.state with
    | some handle => pure handle
    | none => throw <| IO.userError "second edit did not schedule persistence"
  assertTrue (firstHandle != secondHandle) "debounce reused a command handle"
  assertTrue (match secondEdit.command with
    | .batch #[.none, .cancel cancelled, .timeout scheduled 250 (.debounceFired delivered)] =>
        cancelled == firstHandle && scheduled == secondHandle && delivered == secondHandle
    | _ => false) "debounce did not cancel then replace the timer"

  let stale := update secondEdit.state (.debounceFired firstHandle)
  assertTrue (stale.state.text == "second" && isNone stale.command)
    "stale debounce completion changed state"
  let saving := update secondEdit.state (.debounceFired secondHandle)
  let saveHandle ← match saving.command with
    | .storageSet handle "leanrx.notes" "second" _ => pure handle
    | _ => throw <| IO.userError "active debounce did not return storageSet"
  let staleStored := update saving.state (.stored firstHandle (.ok ()))
  assertTrue (statusText staleStored.state == "Saving")
    "stale storage completion overwrote active persistence"
  let failed := update saving.state (.stored saveHandle (.error {
    code := "QUOTA", message := "quota exceeded"
  }))
  assertTrue (statusText failed.state == "Save failed: quota exceeded")
    "storage failure was not user-visible"

  let disposed := update saving.state .dispose
  assertTrue (disposed.state.disposed && match disposed.command with
    | .batch #[.none, .cancel handle] => handle == saveHandle
    | _ => false) "disposal did not cancel owned persistence"
  let ignored := update disposed.state (.edit "after disposal")
  assertTrue (ignored.state.text == "second" && isNone ignored.command)
    "post-disposal update was not suppressed"

end LeanRxTest.Notes.Model
