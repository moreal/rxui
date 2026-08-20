import LeanRx

open LeanRx LeanRx.Effect LeanRx.Notes

def forged : State := {
  text := "forged"
  restored := .idle
  persistence := .idle
  nextHandle := .first
  disposed := false
}
