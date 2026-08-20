import LeanRx

open LeanRx LeanRx.Effect

def forged : ForeignPort String String := {
  name := "unchecked"
  inputRuntime := inferInstance
  outputRuntime := inferInstance
  mode := .sync
  cancellation := .none
  errors := #[]
  trust := ""
  security := ""
  nativeMock := .ok
}
