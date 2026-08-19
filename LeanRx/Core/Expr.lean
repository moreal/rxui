import LeanRx.Core.Store
import LeanRx.Core.Equality

namespace LeanRx

/-- Closed scalar literals supported by the initial staged language. -/
inductive ScalarLiteral : Type → Type where
  | bool (value : Bool) : ScalarLiteral Bool
  | int (value : Int) : ScalarLiteral Int
  | nat (value : Nat) : ScalarLiteral Nat
  | string (value : String) : ScalarLiteral String

namespace ScalarLiteral

def value : {α : Type} → ScalarLiteral α → α
  | _, .bool value => value
  | _, .int value => value
  | _, .nat value => value
  | _, .string value => value

def debug : {α : Type} → ScalarLiteral α → String
  | _, .bool value => s!"bool({value})"
  | _, .int value => s!"int({value})"
  | _, .nat value => s!"nat({value})"
  | _, .string value => "string(" ++ value.quote ++ ")"

end ScalarLiteral

/-- Supported typed unary scalar operations. -/
inductive UnaryPrim : Type → Type → Type where
  | boolNot : UnaryPrim Bool Bool
  | intNeg : UnaryPrim Int Int
  | natToInt : UnaryPrim Nat Int
  | intToString : UnaryPrim Int String
  | natToString : UnaryPrim Nat String

namespace UnaryPrim

def name : {α β : Type} → UnaryPrim α β → String
  | _, _, .boolNot => "Bool.not"
  | _, _, .intNeg => "Int.neg"
  | _, _, .natToInt => "Nat.toInt"
  | _, _, .intToString => "Int.toString"
  | _, _, .natToString => "Nat.toString"

/-- Native semantics for unary primitives. -/
def eval : {α β : Type} → UnaryPrim α β → α → β
  | _, _, .boolNot, value => !value
  | _, _, .intNeg, value => -value
  | _, _, .natToInt, value => Int.ofNat value
  | _, _, .intToString, value => toString value
  | _, _, .natToString, value => toString value

end UnaryPrim

/-- Supported typed binary scalar operations. -/
inductive BinaryPrim : Type → Type → Type → Type where
  | intAdd : BinaryPrim Int Int Int
  | intSub : BinaryPrim Int Int Int
  | intMul : BinaryPrim Int Int Int
  | intMod : BinaryPrim Int Int Int
  | intEq : BinaryPrim Int Int Bool
  | intLt : BinaryPrim Int Int Bool
  | intLe : BinaryPrim Int Int Bool
  | natAdd : BinaryPrim Nat Nat Nat
  | natSub : BinaryPrim Nat Nat Nat
  | natMul : BinaryPrim Nat Nat Nat
  | natMod : BinaryPrim Nat Nat Nat
  | natEq : BinaryPrim Nat Nat Bool
  | natLt : BinaryPrim Nat Nat Bool
  | natLe : BinaryPrim Nat Nat Bool
  | boolAnd : BinaryPrim Bool Bool Bool
  | boolOr : BinaryPrim Bool Bool Bool
  | stringAppend : BinaryPrim String String String
  | stringEq : BinaryPrim String String Bool

namespace BinaryPrim

def name : {α β γ : Type} → BinaryPrim α β γ → String
  | _, _, _, .intAdd => "Int.add"
  | _, _, _, .intSub => "Int.sub"
  | _, _, _, .intMul => "Int.mul"
  | _, _, _, .intMod => "Int.mod"
  | _, _, _, .intEq => "Int.eq"
  | _, _, _, .intLt => "Int.lt"
  | _, _, _, .intLe => "Int.le"
  | _, _, _, .natAdd => "Nat.add"
  | _, _, _, .natSub => "Nat.sub"
  | _, _, _, .natMul => "Nat.mul"
  | _, _, _, .natMod => "Nat.mod"
  | _, _, _, .natEq => "Nat.eq"
  | _, _, _, .natLt => "Nat.lt"
  | _, _, _, .natLe => "Nat.le"
  | _, _, _, .boolAnd => "Bool.and"
  | _, _, _, .boolOr => "Bool.or"
  | _, _, _, .stringAppend => "String.append"
  | _, _, _, .stringEq => "String.eq"

/-- Native semantics for binary primitives. -/
def eval : {α β γ : Type} → BinaryPrim α β γ → α → β → γ
  | _, _, _, .intAdd, left, right => left + right
  | _, _, _, .intSub, left, right => left - right
  | _, _, _, .intMul, left, right => left * right
  | _, _, _, .intMod, left, right => left % right
  | _, _, _, .intEq, left, right => decide (left = right)
  | _, _, _, .intLt, left, right => decide (left < right)
  | _, _, _, .intLe, left, right => decide (left ≤ right)
  | _, _, _, .natAdd, left, right => left + right
  | _, _, _, .natSub, left, right => left - right
  | _, _, _, .natMul, left, right => left * right
  | _, _, _, .natMod, left, right => left % right
  | _, _, _, .natEq, left, right => decide (left = right)
  | _, _, _, .natLt, left, right => decide (left < right)
  | _, _, _, .natLe, left, right => decide (left ≤ right)
  | _, _, _, .boolAnd, left, right => left && right
  | _, _, _, .boolOr, left, right => left || right
  | _, _, _, .stringAppend, left, right => left ++ right
  | _, _, _, .stringEq, left, right => decide (left = right)

end BinaryPrim

/-- A typed staged expression whose index is its complete source dependency set. -/
inductive RxExpr (Γ : Schema) : DepSet Γ → Type → Type 1 where
  | literal (value : ScalarLiteral α) : RxExpr Γ (DepSet.empty Γ) α
  | readWith (runtime : RuntimeRep α) (field : Field Γ α) :
      RxExpr Γ (DepSet.singleton field) α
  | unary (op : UnaryPrim α β) (value : RxExpr Γ deps α) : RxExpr Γ deps β
  | binary (op : BinaryPrim α β γ)
      (left : RxExpr Γ leftDeps α) (right : RxExpr Γ rightDeps β) :
      RxExpr Γ (DepSet.union leftDeps rightDeps) γ
  | ifThenElse (condition : RxExpr Γ conditionDeps Bool)
      (yes : RxExpr Γ yesDeps α) (no : RxExpr Γ noDeps α) :
      RxExpr Γ (DepSet.union conditionDeps (DepSet.union yesDeps noDeps)) α

namespace RxExpr

/-- Stage a field read only when its value has a canonical runtime code. -/
def read {Γ : Schema} {α : Type} [runtime : RuntimeRep α]
    (field : Field Γ α) : RxExpr Γ (DepSet.singleton field) α :=
  .readWith runtime field

/-- Recover the kernel-checked dependency index as ordinary data. -/
def dependencies {Γ : Schema} {deps : DepSet Γ} {α : Type}
    (_ : RxExpr Γ deps α) : DepSet Γ := deps

/-- Pure native evaluation against a typed logical store. -/
def eval : {Γ : Schema} → {deps : DepSet Γ} → {α : Type} →
    RxExpr Γ deps α → Store Γ → α
  | _, _, _, .literal value, _ => value.value
  | _, _, _, .readWith _ field, store => store.get field
  | _, _, _, .unary op value, store => op.eval (value.eval store)
  | _, _, _, .binary op left right, store => op.eval (left.eval store) (right.eval store)
  | _, _, _, .ifThenElse condition yes no, store =>
      if condition.eval store then yes.eval store else no.eval store

/-- Stable structural debug form, independent of object addresses or hash order. -/
def debug : {Γ : Schema} → {deps : DepSet Γ} → {α : Type} →
    RxExpr Γ deps α → String
  | _, _, _, .literal value => value.debug
  | _, _, _, .readWith _ field => "read(" ++ field.name.quote ++ s!"@{field.index})"
  | _, _, _, .unary op value => op.name ++ "(" ++ value.debug ++ ")"
  | _, _, _, .binary op left right =>
      op.name ++ "(" ++ left.debug ++ "," ++ right.debug ++ ")"
  | _, _, _, .ifThenElse condition yes no =>
      "if(" ++ condition.debug ++ "," ++ yes.debug ++ "," ++ no.debug ++ ")"

end RxExpr

end LeanRx
