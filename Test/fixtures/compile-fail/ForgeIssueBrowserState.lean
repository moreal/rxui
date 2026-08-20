import LeanRx

open LeanRx LeanRx.Effect LeanRx.IssueBrowser

def forged : State := {
  query := "forged"
  issues := #[]
  currentPage := 0
  hasMore := false
  resource := .idle
  active := none
  lastRequest := none
  nextHandle := .first
  disposed := false
}
