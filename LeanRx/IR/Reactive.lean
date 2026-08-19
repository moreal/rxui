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

namespace Literal

def debug : {α : Type} → Literal α → String
  | _, .bool value => s!"bool({value})"
  | _, .string value => "string(" ++ value.quote ++ ")"
  | _, .int value => s!"int({value})"
  | _, .nat value => s!"nat({value})"

end Literal

namespace Unary

def name : {α β : Type} → Unary α β → String
  | _, _, .boolNot => "bool.not"
  | _, _, .intNeg => "int.neg"
  | _, _, .natToInt => "nat.toInt"

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

end Binary

namespace Expr

def debug : {α : Type} → Expr α → String
  | _, .literal value => value.debug
  | _, .input _ index name => "input(" ++ name.quote ++ s!"@{index})"
  | _, .unary op value => op.name ++ "(" ++ value.debug ++ ")"
  | _, .binary op left right => op.name ++ "(" ++ left.debug ++ "," ++ right.debug ++ ")"
  | _, .conditional condition yes no =>
      "if(" ++ condition.debug ++ "," ++ yes.debug ++ "," ++ no.debug ++ ")"

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
    code := "LRX-LOWER-001"
    phase := "reactive-ir"
    message := s!"unsupported browser-lowerable computation: {name}"
    span
  }

end LeanRx.ReactiveIR
