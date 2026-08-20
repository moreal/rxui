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
  let retryEdit := update failed.state (.edit "retry")
  assertTrue (statusText retryEdit.state == "Waiting to save")
    "a new edit did not clear the stale save failure"
  let retryHandle ← match pendingHandle retryEdit.state with
    | some handle => pure handle
    | none => throw <| IO.userError "retry edit did not schedule persistence"
  let retrySaving := update retryEdit.state (.debounceFired retryHandle)
  let retrySaveHandle ← match retrySaving.command with
    | .storageSet handle "leanrx.notes" "retry" _ => pure handle
    | _ => throw <| IO.userError "retry debounce did not return storageSet"
  let retrySaved := update retrySaving.state (.stored retrySaveHandle (.ok ()))
  assertTrue (statusText retrySaved.state == "Saved")
    "successful retry did not clear the stale save failure"

  let failingRestore := update initial .restore
  let failingRestoreHandle ← match failingRestore.command with
    | .storageGet handle "leanrx.notes" _ => pure handle
    | _ => throw <| IO.userError "failing restore did not return storageGet"
  let restoreFailed := update failingRestore.state (.restored failingRestoreHandle (.error {
    code := "READ", message := "restore broke"
  }))
  let editAfterRestoreFailure := update restoreFailed.state (.edit "local")
  let restoreRetryHandle ← match pendingHandle editAfterRestoreFailure.state with
    | some handle => pure handle
    | none => throw <| IO.userError "edit after restore failure did not schedule persistence"
  let restoreRetrySaving := update editAfterRestoreFailure.state
    (.debounceFired restoreRetryHandle)
  let restoreSaveHandle ← match restoreRetrySaving.command with
    | .storageSet handle "leanrx.notes" "local" _ => pure handle
    | _ => throw <| IO.userError "restore-failure retry did not return storageSet"
  let restoreRetrySaved := update restoreRetrySaving.state (.stored restoreSaveHandle (.ok ()))
  assertTrue (statusText restoreRetrySaved.state == "Restore failed: restore broke")
    "successful save incorrectly hid the independent restore failure"

  assertTrue (match (Spec.create "").check with
    | .error error => error.code == "LRX-PORT-501"
    | .ok _ => false) "empty Notes spec returned the wrong diagnostic"

  let disposed := update saving.state .dispose
  assertTrue (disposed.state.disposed && match disposed.command with
    | .batch #[.none, .cancel handle] => handle == saveHandle
    | _ => false) "disposal did not cancel owned persistence"
  let ignored := update disposed.state (.edit "after disposal")
  assertTrue (ignored.state.text == "second" && isNone ignored.command)
    "post-disposal update was not suppressed"

end LeanRxTest.Notes.Model
