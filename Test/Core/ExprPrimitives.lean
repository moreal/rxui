import LeanRx.Core.Expr
import Test.Core.Expr

namespace LeanRxTest.ExprPrimitives

private def expect [BEq α] (label : String) (expected actual : α) : IO Unit :=
  unless expected == actual do
    throw <| IO.userError s!"primitive mismatch: {label}"

private def evalEmpty {deps : LeanRx.DepSet (.empty : LeanRx.Schema)} {α : Type}
    (expr : LeanRx.RxExpr .empty deps α) : α :=
  expr.eval .empty

def run : IO Unit := do
  expect "literal" (7 : Int) <| evalEmpty (.literal (.int 7))
  expect "field read" (12 : Int) <|
    (LeanRx.RxExpr.read LeanRxTest.Expr.price).eval (LeanRxTest.Expr.pricingStore 12 4 40)
  expect "Bool.not" false <| evalEmpty <| .unary .boolNot (.literal (.bool true))
  expect "Int.neg" (-7 : Int) <| evalEmpty <| .unary .intNeg (.literal (.int 7))
  expect "Nat.toInt" (7 : Int) <| evalEmpty <| .unary .natToInt (.literal (.nat 7))
  expect "Int.toString" "-9007199254740993" <| evalEmpty <|
    .unary .intToString (.literal (.int (-9007199254740993)))
  expect "Nat.toString" "9007199254740993" <| evalEmpty <|
    .unary .natToString (.literal (.nat 9007199254740993))
  expect "Int.add" (12 : Int) <| evalEmpty <|
    .binary .intAdd (.literal (.int 7)) (.literal (.int 5))
  expect "Int.sub" (2 : Int) <| evalEmpty <|
    .binary .intSub (.literal (.int 7)) (.literal (.int 5))
  expect "Int.mul" (35 : Int) <| evalEmpty <|
    .binary .intMul (.literal (.int 7)) (.literal (.int 5))
  expect "Int.mod" (2 : Int) <| evalEmpty <|
    .binary .intMod (.literal (.int 7)) (.literal (.int 5))
  expect "Int.mod negative" (3 : Int) <| evalEmpty <|
    .binary .intMod (.literal (.int (-7))) (.literal (.int 5))
  expect "Int.mod zero" (7 : Int) <| evalEmpty <|
    .binary .intMod (.literal (.int 7)) (.literal (.int 0))
  expect "Int.eq" true <| evalEmpty <|
    .binary .intEq (.literal (.int (-7))) (.literal (.int (-7)))
  expect "Int.lt" true <| evalEmpty <|
    .binary .intLt (.literal (.int (-7))) (.literal (.int 5))
  expect "Int.le" true <| evalEmpty <|
    .binary .intLe (.literal (.int 5)) (.literal (.int 5))
  expect "Nat.add" 12 <| evalEmpty <|
    .binary .natAdd (.literal (.nat 7)) (.literal (.nat 5))
  expect "Nat.sub" 0 <| evalEmpty <|
    .binary .natSub (.literal (.nat 5)) (.literal (.nat 7))
  expect "Nat.mul" 35 <| evalEmpty <|
    .binary .natMul (.literal (.nat 7)) (.literal (.nat 5))
  expect "Nat.mod" 2 <| evalEmpty <|
    .binary .natMod (.literal (.nat 7)) (.literal (.nat 5))
  expect "Nat.mod zero" 7 <| evalEmpty <|
    .binary .natMod (.literal (.nat 7)) (.literal (.nat 0))
  expect "Nat.eq" false <| evalEmpty <|
    .binary .natEq (.literal (.nat 7)) (.literal (.nat 5))
  expect "Nat.lt" true <| evalEmpty <|
    .binary .natLt (.literal (.nat 5)) (.literal (.nat 7))
  expect "Nat.le" true <| evalEmpty <|
    .binary .natLe (.literal (.nat 7)) (.literal (.nat 7))
  expect "Bool.and" false <| evalEmpty <|
    .binary .boolAnd (.literal (.bool true)) (.literal (.bool false))
  expect "Bool.or" true <| evalEmpty <|
    .binary .boolOr (.literal (.bool true)) (.literal (.bool false))
  expect "String.append" "LeanRx" <| evalEmpty <|
    .binary .stringAppend (.literal (.string "Lean")) (.literal (.string "Rx"))
  expect "String.eq" true <| evalEmpty <|
    .binary .stringEq (.literal (.string "한글")) (.literal (.string "한글"))

end LeanRxTest.ExprPrimitives
