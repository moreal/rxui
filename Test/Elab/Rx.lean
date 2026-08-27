import LeanRx

namespace LeanRxTest.Elab.Rx

open LeanRx
open scoped LeanRxDsl

private abbrev RxSchema : Schema :=
  .field "count" Int <| .field "label" String <| .field "steps" Nat .empty

private def count : Field RxSchema Int := .here
private def labelField : Field RxSchema String := .there .here
private def steps : Field RxSchema Nat := .there (.there .here)

private def expectEqual (name : String) (staged reference : RxExpr RxSchema deps α) :
    IO Unit := do
  unless staged.debug == reference.debug do
    throw <| IO.userError
      s!"rx% staged {name} as {staged.debug}, expected {reference.debug}"

/-- `rx%` must stage exactly the tree the explicit constructor API builds:
identical primitives, identical literal codes, and identical dependency sets. -/
def run : IO Unit := do
  expectEqual "arithmetic" (rx% count * 2 + count % 3)
    (RxExpr.binary .intAdd
      (RxExpr.binary .intMul (RxExpr.read count) (RxExpr.literal (.int 2)))
      (RxExpr.binary .intMod (RxExpr.read count) (RxExpr.literal (.int 3))))
  expectEqual "conditional" (rx% if count == 0 then "zero" else "nonzero")
    (RxExpr.ifThenElse
      (RxExpr.binary .intEq (RxExpr.read count) (RxExpr.literal (.int 0)))
      (RxExpr.literal (.string "zero")) (RxExpr.literal (.string "nonzero")))
  expectEqual "interpolation" (rx% s!"Count: {count} of {steps}")
    (RxExpr.binary .stringAppend
      (RxExpr.binary .stringAppend
        (RxExpr.binary .stringAppend (RxExpr.literal (.string "Count: "))
          (RxExpr.unary .intToString (RxExpr.read count)))
        (RxExpr.literal (.string " of ")))
      (RxExpr.unary .natToString (RxExpr.read steps)))
  expectEqual "boolean" (rx% !(count < 1) && (labelField != "" || count ≤ 9))
    (RxExpr.binary .boolAnd
      (RxExpr.unary .boolNot
        (RxExpr.binary .intLt (RxExpr.read count) (RxExpr.literal (.int 1))))
      (RxExpr.binary .boolOr
        (RxExpr.unary .boolNot
          (RxExpr.binary .stringEq (RxExpr.read labelField)
            (RxExpr.literal (.string ""))))
        (RxExpr.binary .intLe (RxExpr.read count) (RxExpr.literal (.int 9)))))
  expectEqual "nat literals" (rx% steps + 1)
    (RxExpr.binary .natAdd (RxExpr.read steps) (RxExpr.literal (.nat 1)))
  expectEqual "negation and text" (rx% toString (-count) ++ labelField)
    (RxExpr.binary .stringAppend
      (RxExpr.unary .intToString (RxExpr.unary .intNeg (RxExpr.read count)))
      (RxExpr.read labelField))
  expectEqual "trim" (rx% trim labelField)
    (RxExpr.unary .stringTrim (RxExpr.read labelField))
  expectEqual "trim composed" (rx% trim (labelField ++ "!"))
    (RxExpr.unary .stringTrim
      (RxExpr.binary .stringAppend (RxExpr.read labelField)
        (RxExpr.literal (.string "!"))))
  let staged := rx% count * 2
  expectEqual "staged reuse" (rx% if staged < 10 then staged else count)
    (RxExpr.ifThenElse
      (RxExpr.binary .intLt staged (RxExpr.literal (.int 10)))
      staged (RxExpr.read count))
  unless (rx% toString count ++ toString steps).dependencies.debug == "{0,2}" do
    throw <| IO.userError "rx% lost the canonical dependency union"

end LeanRxTest.Elab.Rx
