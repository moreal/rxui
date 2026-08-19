import LeanRx.Lower.RxExpr
import Test.Core.Expr

namespace LeanRxTest.Lower.RxExpr

open LeanRxTest.Expr

def run : IO Unit := do
  let subtotalIr := LeanRx.Lower.rxExpr subtotal
  unless subtotalIr.debug ==
      "int.mul(input(\"price\"@0),input(\"quantity\"@1))" do
    throw <| IO.userError s!"Reactive IR lowering changed: {subtotalIr.debug}"
  let conditionalIr := LeanRx.Lower.rxExpr choose
  unless conditionalIr.debug ==
      "if(input(\"condition\"@0),input(\"yes\"@1),input(\"no\"@2))" do
    throw <| IO.userError s!"conditional Reactive IR lowering changed: {conditionalIr.debug}"
  let span : LeanRx.SourceSpan :=
    { file := "app/Unsupported.lean"
      start := { line := 4, column := 3, byteOffset := 30 }
      stop := { line := 4, column := 12, byteOffset := 39 } }
  let unsupported : Except LeanRx.ReactiveIR.LowerError (LeanRx.ReactiveIR.Expr Int) :=
    LeanRx.ReactiveIR.rejectUnsupported "App.arbitraryRecursiveFunction" span
  match unsupported with
  | .ok _ => throw <| IO.userError "unsupported computation produced Reactive IR"
  | .error error =>
      unless error.code == "LRX-BE-020" && error.phase == "reactive-ir" &&
          error.span == span && error.message.contains "App.arbitraryRecursiveFunction" do
        throw <| IO.userError "unsupported lowering lost its source-linked diagnostic"

end LeanRxTest.Lower.RxExpr
