import LeanRx.Core.Expr

/-! Typeclass-directed smart constructors for the staged expression surface.

The `rx%` elaborator maps ordinary Lean operator syntax onto these helpers so
type inference selects the exact closed primitive. Every helper produces the
same constructor tree a hand-written `RxExpr` would; no new primitive, runtime
code, or dependency behaviour is introduced here. -/

namespace LeanRx

/-- Scalar types with a staged addition primitive. -/
class RxAdd (α : Type) where
  prim : BinaryPrim α α α

instance : RxAdd Int := ⟨.intAdd⟩
instance : RxAdd Nat := ⟨.natAdd⟩

/-- Scalar types with a staged subtraction primitive. -/
class RxSub (α : Type) where
  prim : BinaryPrim α α α

instance : RxSub Int := ⟨.intSub⟩
instance : RxSub Nat := ⟨.natSub⟩

/-- Scalar types with a staged multiplication primitive. -/
class RxMul (α : Type) where
  prim : BinaryPrim α α α

instance : RxMul Int := ⟨.intMul⟩
instance : RxMul Nat := ⟨.natMul⟩

/-- Scalar types with a staged remainder primitive. -/
class RxMod (α : Type) where
  prim : BinaryPrim α α α

instance : RxMod Int := ⟨.intMod⟩
instance : RxMod Nat := ⟨.natMod⟩

/-- Scalar types with staged strict and non-strict order primitives. -/
class RxOrd (α : Type) where
  lt : BinaryPrim α α Bool
  le : BinaryPrim α α Bool

instance : RxOrd Int := ⟨.intLt, .intLe⟩
instance : RxOrd Nat := ⟨.natLt, .natLe⟩

/-- Scalar types with a staged decidable-equality primitive. -/
class RxEqPrim (α : Type) where
  prim : BinaryPrim α α Bool

instance : RxEqPrim Int := ⟨.intEq⟩
instance : RxEqPrim Nat := ⟨.natEq⟩
instance : RxEqPrim String := ⟨.stringEq⟩

/-- Scalar types whose numeric literals stage into a closed scalar literal. -/
class RxNumLit (α : Type) where
  lit : Nat → ScalarLiteral α

instance : RxNumLit Int := ⟨fun value => .int (Int.ofNat value)⟩
instance : RxNumLit Nat := ⟨.nat⟩

/-- Scalar values that lift into a staged literal of the same closed type. -/
class RxLiftLit (α : Type) where
  lit : α → ScalarLiteral α

instance : RxLiftLit Bool := ⟨.bool⟩
instance : RxLiftLit Int := ⟨.int⟩
instance : RxLiftLit Nat := ⟨.nat⟩
instance : RxLiftLit String := ⟨.string⟩

/-- Scalar types with a staged rendering primitive into text. -/
class RxToText (α : Type) where
  toText : {Γ : Schema} → {deps : DepSet Γ} →
    RxExpr Γ deps α → RxExpr Γ deps String

instance : RxToText Int := ⟨fun value => .unary .intToString value⟩
instance : RxToText Nat := ⟨fun value => .unary .natToString value⟩
instance : RxToText String := ⟨fun value => value⟩

namespace RxExpr

/-- Staged `+` selected by scalar type. -/
def addOp [RxAdd α] (left : RxExpr Γ leftDeps α) (right : RxExpr Γ rightDeps α) :
    RxExpr Γ (DepSet.union leftDeps rightDeps) α :=
  .binary RxAdd.prim left right

/-- Staged `-` selected by scalar type. -/
def subOp [RxSub α] (left : RxExpr Γ leftDeps α) (right : RxExpr Γ rightDeps α) :
    RxExpr Γ (DepSet.union leftDeps rightDeps) α :=
  .binary RxSub.prim left right

/-- Staged `*` selected by scalar type. -/
def mulOp [RxMul α] (left : RxExpr Γ leftDeps α) (right : RxExpr Γ rightDeps α) :
    RxExpr Γ (DepSet.union leftDeps rightDeps) α :=
  .binary RxMul.prim left right

/-- Staged `%` selected by scalar type. -/
def modOp [RxMod α] (left : RxExpr Γ leftDeps α) (right : RxExpr Γ rightDeps α) :
    RxExpr Γ (DepSet.union leftDeps rightDeps) α :=
  .binary RxMod.prim left right

/-- Staged `<` selected by scalar type. -/
def ltOp [RxOrd α] (left : RxExpr Γ leftDeps α) (right : RxExpr Γ rightDeps α) :
    RxExpr Γ (DepSet.union leftDeps rightDeps) Bool :=
  .binary RxOrd.lt left right

/-- Staged `≤` selected by scalar type. -/
def leOp [RxOrd α] (left : RxExpr Γ leftDeps α) (right : RxExpr Γ rightDeps α) :
    RxExpr Γ (DepSet.union leftDeps rightDeps) Bool :=
  .binary RxOrd.le left right

/-- Staged `==` selected by scalar type. -/
def eqOp [RxEqPrim α] (left : RxExpr Γ leftDeps α) (right : RxExpr Γ rightDeps α) :
    RxExpr Γ (DepSet.union leftDeps rightDeps) Bool :=
  .binary RxEqPrim.prim left right

/-- Staged `!=` selected by scalar type. -/
def neOp [RxEqPrim α] (left : RxExpr Γ leftDeps α) (right : RxExpr Γ rightDeps α) :
    RxExpr Γ (DepSet.union leftDeps rightDeps) Bool :=
  .unary .boolNot (.binary RxEqPrim.prim left right)

/-- Staged boolean conjunction. -/
def andOp (left : RxExpr Γ leftDeps Bool) (right : RxExpr Γ rightDeps Bool) :
    RxExpr Γ (DepSet.union leftDeps rightDeps) Bool :=
  .binary .boolAnd left right

/-- Staged boolean disjunction. -/
def orOp (left : RxExpr Γ leftDeps Bool) (right : RxExpr Γ rightDeps Bool) :
    RxExpr Γ (DepSet.union leftDeps rightDeps) Bool :=
  .binary .boolOr left right

/-- Staged boolean negation. -/
def notOp (value : RxExpr Γ deps Bool) : RxExpr Γ deps Bool :=
  .unary .boolNot value

/-- Staged integer negation. -/
def negOp (value : RxExpr Γ deps Int) : RxExpr Γ deps Int :=
  .unary .intNeg value

/-- Staged text concatenation. -/
def appendOp (left : RxExpr Γ leftDeps String) (right : RxExpr Γ rightDeps String) :
    RxExpr Γ (DepSet.union leftDeps rightDeps) String :=
  .binary .stringAppend left right

/-- The staged ASCII-whitespace trim (ADR-0055): `String`-only, the one
sealed normalization in the component expression language. -/
def trimOp (value : RxExpr Γ deps String) : RxExpr Γ deps String :=
  .unary .stringTrim value

/-- Staged numeric literal selected by scalar type. -/
def numLit [RxNumLit α] (value : Nat) : RxExpr Γ (DepSet.empty Γ) α :=
  .literal (RxNumLit.lit value)

/-- Staged text literal. -/
def strLit (value : String) : RxExpr Γ (DepSet.empty Γ) String :=
  .literal (.string value)

/-- Staged boolean literal. -/
def boolLit (value : Bool) : RxExpr Γ (DepSet.empty Γ) Bool :=
  .literal (.bool value)

/-- Stage an ordinary scalar value as a literal. -/
def liftLit [RxLiftLit α] (value : α) : RxExpr Γ (DepSet.empty Γ) α :=
  .literal (RxLiftLit.lit value)

/-- Staged `toString` selected by scalar type. -/
def toText [RxToText α] (value : RxExpr Γ deps α) : RxExpr Γ deps String :=
  RxToText.toText value

/-- Staged conditional with the canonical dependency union. -/
def condOp (condition : RxExpr Γ conditionDeps Bool)
    (yes : RxExpr Γ yesDeps α) (no : RxExpr Γ noDeps α) :
    RxExpr Γ (DepSet.union conditionDeps (DepSet.union yesDeps noDeps)) α :=
  .ifThenElse condition yes no

end RxExpr

end LeanRx
