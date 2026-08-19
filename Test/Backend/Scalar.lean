import LeanRx.Backend.Scalar
import LeanRx.Backend.JsPrinter
import LeanRx.Lower.RxExpr
import Test.Core.Expr

namespace LeanRxTest.Backend.Scalar

open LeanRxTest.Expr

private def emit (name : String) (inputs : Array String) (value : LeanRx.ReactiveIR.Expr α) :
    IO LeanRx.Backend.Scalar.Emitted :=
  match LeanRx.Backend.Scalar.moduleFor name inputs value with
  | .ok emitted => pure emitted
  | .error error => throw <| IO.userError s!"scalar module emission failed: {error.code}"

def run : IO Unit := do
  let subtotalModule ← emit "subtotal" #["price", "quantity", "threshold"] <|
    LeanRx.Lower.rxExpr subtotal
  let subtotalSource ← match LeanRx.Js.Printer.module .readable subtotalModule.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError error.message
  unless subtotalSource ==
      "function subtotal(price, quantity, threshold) {\n  return (price * quantity);\n}\nexport { subtotal };\n" do
    throw <| IO.userError s!"scalar module golden changed:\n{subtotalSource}"
  let intMod : LeanRx.ReactiveIR.Expr Int := .binary .intMod
    (.input .int 0 "left") (.input .int 1 "right")
  let modModule ← emit "mod" #["left", "right"] intMod
  unless modModule.module.declarations.size == 2 do
    throw <| IO.userError "Int.mod did not emit exactly one semantic helper"
  let repeatedMod : LeanRx.ReactiveIR.Expr Int := .binary .intAdd intMod intMod
  let repeatedModule ← emit "repeatedMod" #["left", "right"] repeatedMod
  unless repeatedModule.module.declarations.size == 2 do
    throw <| IO.userError "repeated Int.mod emitted duplicate semantic helpers"
  let display : LeanRx.ReactiveIR.Expr String :=
    .unary .intToString (.input .int 0 "String")
  let shadowed ← emit "String" #["String"] display
  let shadowedSource ← match LeanRx.Js.Printer.module .compact shadowed.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError error.message
  unless shadowedSource.contains "function String_2(String_3)" &&
      shadowedSource.contains "String(String_3)" do
    throw <| IO.userError "user identifiers shadowed the backend-owned String builtin"
  let badInput : LeanRx.ReactiveIR.Expr Int := .input .int 2 "missing"
  match LeanRx.Backend.Scalar.moduleFor "bad" #["only"] badInput with
  | .ok _ => throw <| IO.userError "out-of-range Reactive IR input emitted JavaScript"
  | .error error =>
      unless error.code == "LRX-JS-013" do
        throw <| IO.userError "out-of-range input returned the wrong diagnostic"

end LeanRxTest.Backend.Scalar
