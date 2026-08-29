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

/-- The declaration that a control's state is the program's and not the
browser's (ADR-0104), for the hand-written backends. It is the same claim
`StaticAttr.ownedState` makes in the checked-component pipeline and it is
spelled once here so both say it identically: a control whose `value` or
`checked` this backend writes from its own state has that property rewritten
at every mount and every update, so the copy the browser saves into a
session-history entry can only land *after* the write and leave the DOM
disagreeing with the state it mirrors.

The rule is the property write, not the tag: a control the program never
writes — Issue Browser's query field, whose mount value is a literal it never
revisits — keeps the browser's restoration, because nothing it could
contradict is being claimed. Emitted as the last static attribute, directly
before the property write it declares ownership of, which is where the
checked pipeline puts it too. -/
def ownedState (host : Ident) (target : Expr) : Expr :=
  call host [target, .literal (.string "autocomplete"), .literal (.string "off")]

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
