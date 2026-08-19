import LeanRx.Backend.FormDom
import LeanRx.Backend.JsPrinter

namespace LeanRxTest.Backend.FormDom

open LeanRx LeanRx.Form LeanRx.Js

private def ident (name : String) : IO Ident :=
  match Ident.checked name with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"test identifier failed: {error.code}"

def run : IO Unit := do
  let listenValue ← ident "listenValue"
  let listenChecked ← ident "listenChecked"
  let listenKey ← ident "listenKey"
  let listenFocus ← ident "listenFocus"
  let listenSubmit ← ident "listenSubmit"
  let runtime : Backend.FormDom.ListenerRuntime := {
    value := listenValue
    checked := listenChecked
    key := listenKey
    focus := listenFocus
    submit := listenSubmit
  }
  let target := Expr.ident (← ident "target")
  let state := Expr.ident (← ident "state")
  let context := Expr.ident (← ident "context")
  let handler ← ident "handler"
  let render (value : Expr) : IO String :=
    match Js.Printer.expr .compact value with
    | .ok source => pure source
    | .error error => throw <| IO.userError s!"form DOM helper failed: {error.code}"
  unless (← render <| Backend.FormDom.setProperty (← ident "setProperty") target
      DomProperty.disabled (.literal (.boolean true))) ==
      "setProperty(target,\"disabled\",true)" do
    throw <| IO.userError "typed property lowering changed"
  unless (← render <| Backend.FormDom.listen runtime ControlEvent.change target state context
      handler) == "listenValue(target,\"change\",state,context,handler)" &&
      (← render <| Backend.FormDom.listen runtime ControlEvent.checkedChange target state context
        handler) == "listenChecked(target,\"change\",state,context,handler)" &&
      (← render <| Backend.FormDom.listen runtime ControlEvent.submit target state context
        handler) == "listenSubmit(target,state,context,handler)" do
    throw <| IO.userError "typed form listener lowering changed"

end LeanRxTest.Backend.FormDom
