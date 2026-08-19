import LeanRx.Core.Expr
import LeanRx.IR.Reactive

namespace LeanRx.Lower

private def literal : {α : Type} → ScalarLiteral α → ReactiveIR.Literal α
  | _, .bool value => .bool value
  | _, .string value => .string value
  | _, .int value => .int value
  | _, .nat value => .nat value

private def unary : {α β : Type} → UnaryPrim α β → ReactiveIR.Unary α β
  | _, _, .boolNot => .boolNot
  | _, _, .intNeg => .intNeg
  | _, _, .natToInt => .natToInt
  | _, _, .intToString => .intToString
  | _, _, .natToString => .natToString

private def binary : {α β γ : Type} → BinaryPrim α β γ → ReactiveIR.Binary α β γ
  | _, _, _, .intAdd => .intAdd
  | _, _, _, .intSub => .intSub
  | _, _, _, .intMul => .intMul
  | _, _, _, .intMod => .intMod
  | _, _, _, .intEq => .intEq
  | _, _, _, .intLt => .intLt
  | _, _, _, .intLe => .intLe
  | _, _, _, .natAdd => .natAdd
  | _, _, _, .natSub => .natSub
  | _, _, _, .natMul => .natMul
  | _, _, _, .natMod => .natMod
  | _, _, _, .natEq => .natEq
  | _, _, _, .natLt => .natLt
  | _, _, _, .natLe => .natLe
  | _, _, _, .boolAnd => .boolAnd
  | _, _, _, .boolOr => .boolOr
  | _, _, _, .stringAppend => .stringAppend
  | _, _, _, .stringEq => .stringEq

/-- Pure staged-core to custom-Reactive-IR lowering. -/
def rxExpr : {Γ : Schema} → {deps : DepSet Γ} → {α : Type} →
    RxExpr Γ deps α → ReactiveIR.Expr α
  | _, _, _, .literal value => .literal (literal value)
  | _, _, _, .readWith runtime field =>
      .input runtime.runtimeType field.index field.name
  | _, _, _, .unary op value => .unary (unary op) (rxExpr value)
  | _, _, _, .binary op left right => .binary (binary op) (rxExpr left) (rxExpr right)
  | _, _, _, .ifThenElse condition yes no =>
      .conditional (rxExpr condition) (rxExpr yes) (rxExpr no)
  | _, _, _, .vectorGetWith element values index =>
      .vectorGet element.runtimeType (rxExpr values) (rxExpr index)

end LeanRx.Lower
