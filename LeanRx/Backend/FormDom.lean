import LeanRx.Backend.JsAst
import LeanRx.Form.Dom

namespace LeanRx.Backend.FormDom

open LeanRx.Js
open LeanRx.Form

/-- Compiler-owned host names for the closed form event adapters. -/
structure ListenerRuntime where
  value : Ident
  checked : Ident
  key : Ident
  focus : Ident
  submit : Ident

private def call (name : Ident) (args : List Expr) : Expr :=
  .call (.ident name) (.ofList args)

/-- Lower a typed property capability; callers never supply its JavaScript
property name. -/
def setProperty (host : Ident) (target : Expr) (property : DomProperty α)
    (value : Expr) : Expr :=
  call host [target, .literal (.string property.name), value]

/-- Lower a typed event capability to its only permitted payload adapter. The
submit adapter has a deliberately different host signature because it owns
`preventDefault`. -/
def listen (runtime : ListenerRuntime) (event : ControlEvent α) (target state context : Expr)
    (handler : Ident) : Expr :=
  match event with
  | .input | .change =>
      call runtime.value [target, .literal (.string event.name), state, context, .ident handler]
  | .checkedChange =>
      call runtime.checked [target, .literal (.string event.name), state, context, .ident handler]
  | .keyDown =>
      call runtime.key [target, .literal (.string event.name), state, context, .ident handler]
  | .focus | .blur =>
      call runtime.focus [target, .literal (.string event.name), state, context, .ident handler]
  | .submit => call runtime.submit [target, state, context, .ident handler]

end LeanRx.Backend.FormDom
