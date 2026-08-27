import LeanRx.Core.RuntimeRep
import LeanRx.Core.SourceInfo

namespace LeanRx.ReactiveIR

inductive Literal : Type → Type where
  | bool (value : Bool) : Literal Bool
  | string (value : String) : Literal String
  | int (value : Int) : Literal Int
  | nat (value : Nat) : Literal Nat

inductive Unary : Type → Type → Type where
  | boolNot : Unary Bool Bool
  | intNeg : Unary Int Int
  | natToInt : Unary Nat Int
  | intToString : Unary Int String
  | natToString : Unary Nat String
  | stringTrim : Unary String String

inductive Binary : Type → Type → Type → Type where
  | intAdd : Binary Int Int Int
  | intSub : Binary Int Int Int
  | intMul : Binary Int Int Int
  | intMod : Binary Int Int Int
  | intEq : Binary Int Int Bool
  | intLt : Binary Int Int Bool
  | intLe : Binary Int Int Bool
  | natAdd : Binary Nat Nat Nat
  | natSub : Binary Nat Nat Nat
  | natMul : Binary Nat Nat Nat
  | natMod : Binary Nat Nat Nat
  | natEq : Binary Nat Nat Bool
  | natLt : Binary Nat Nat Bool
  | natLe : Binary Nat Nat Bool
  | boolAnd : Binary Bool Bool Bool
  | boolOr : Binary Bool Bool Bool
  | stringAppend : Binary String String String
  | stringEq : Binary String String Bool

inductive Expr : Type → Type 1 where
  | literal (value : Literal α) : Expr α
  | input (runtime : RuntimeType α) (index : Nat) (name : String) : Expr α
  | unary (op : Unary α β) (value : Expr α) : Expr β
  | binary (op : Binary α β γ) (left : Expr α) (right : Expr β) : Expr γ
  | conditional (condition : Expr Bool) (yes no : Expr α) : Expr α
  | vectorGet (element : RuntimeType α) (values : Expr (Vector α length))
      (index : Expr (Fin length)) : Expr α

namespace Literal

def debug : {α : Type} → Literal α → String
  | _, .bool value => s!"bool({value})"
  | _, .string value => "string(" ++ value.quote ++ ")"
  | _, .int value => s!"int({value})"
  | _, .nat value => s!"nat({value})"

def runtimeTypeId : {α : Type} → Literal α → RuntimeTypeId
  | _, .bool _ => .bool
  | _, .string _ => .string
  | _, .int _ => .int
  | _, .nat _ => .nat

end Literal

namespace Unary

def name : {α β : Type} → Unary α β → String
  | _, _, .boolNot => "bool.not"
  | _, _, .intNeg => "int.neg"
  | _, _, .natToInt => "nat.toInt"
  | _, _, .intToString => "int.toString"
  | _, _, .natToString => "nat.toString"
  | _, _, .stringTrim => "string.trim"

def resultTypeId : {α β : Type} → Unary α β → RuntimeTypeId
  | _, _, .boolNot => .bool
  | _, _, .intNeg => .int
  | _, _, .natToInt => .int
  | _, _, .intToString => .string
  | _, _, .natToString => .string
  | _, _, .stringTrim => .string

end Unary

namespace Binary

def name : {α β γ : Type} → Binary α β γ → String
  | _, _, _, .intAdd => "int.add"
  | _, _, _, .intSub => "int.sub"
  | _, _, _, .intMul => "int.mul"
  | _, _, _, .intMod => "int.mod"
  | _, _, _, .intEq => "int.eq"
  | _, _, _, .intLt => "int.lt"
  | _, _, _, .intLe => "int.le"
  | _, _, _, .natAdd => "nat.add"
  | _, _, _, .natSub => "nat.sub"
  | _, _, _, .natMul => "nat.mul"
  | _, _, _, .natMod => "nat.mod"
  | _, _, _, .natEq => "nat.eq"
  | _, _, _, .natLt => "nat.lt"
  | _, _, _, .natLe => "nat.le"
  | _, _, _, .boolAnd => "bool.and"
  | _, _, _, .boolOr => "bool.or"
  | _, _, _, .stringAppend => "string.append"
  | _, _, _, .stringEq => "string.eq"

def resultTypeId : {α β γ : Type} → Binary α β γ → RuntimeTypeId
  | _, _, _, .intAdd | _, _, _, .intSub | _, _, _, .intMul | _, _, _, .intMod => .int
  | _, _, _, .intEq | _, _, _, .intLt | _, _, _, .intLe => .bool
  | _, _, _, .natAdd | _, _, _, .natSub | _, _, _, .natMul | _, _, _, .natMod => .nat
  | _, _, _, .natEq | _, _, _, .natLt | _, _, _, .natLe => .bool
  | _, _, _, .boolAnd | _, _, _, .boolOr => .bool
  | _, _, _, .stringAppend => .string
  | _, _, _, .stringEq => .bool

end Binary

namespace Expr

def runtimeTypeId : {α : Type} → Expr α → RuntimeTypeId
  | _, .literal value => value.runtimeTypeId
  | _, .input runtime _ _ => runtime.id
  | _, .unary op _ => op.resultTypeId
  | _, .binary op _ _ => op.resultTypeId
  | _, .conditional _ yes _ => runtimeTypeId yes
  | _, .vectorGet element _ _ => element.id

def debug : {α : Type} → Expr α → String
  | _, .literal value => value.debug
  | _, .input _ index name => "input(" ++ name.quote ++ s!"@{index})"
  | _, .unary op value => op.name ++ "(" ++ value.debug ++ ")"
  | _, .binary op left right => op.name ++ "(" ++ left.debug ++ "," ++ right.debug ++ ")"
  | _, .conditional condition yes no =>
      "if(" ++ condition.debug ++ "," ++ yes.debug ++ "," ++ no.debug ++ ")"
  | _, .vectorGet _ values index =>
      "vector.get(" ++ values.debug ++ "," ++ index.debug ++ ")"

end Expr

structure LowerError where
  code : String
  phase : String
  message : String
  span : SourceSpan
deriving Repr, BEq

/-- Future elaboration paths use this fail-closed boundary for ordinary Lean
terms that are not represented by the staged scalar core. -/
def rejectUnsupported {α : Type} (name : String) (span : SourceSpan) :
    Except LowerError (Expr α) :=
  .error {
    code := "LRX-BE-020"
    phase := "reactive-ir"
    message := s!"unsupported browser-lowerable computation: {name}"
    span
  }

end LeanRx.ReactiveIR
