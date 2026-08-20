import LeanRx

open LeanRx LeanRx.Effect

def forged : ForeignPort String String := {
  name := "unchecked"
  inputType := .runtime .string
  outputType := .runtime .string
  mode := .sync
  cancellation := .none
  errors := #[]
  trust := ""
  security := ""
  nativeMock := .ok
}
