import LeanRx.Core.Expr

namespace LeanRxTest.Expr

abbrev Pricing : LeanRx.Schema :=
  .field "price" Int <| .field "quantity" Int <| .field "threshold" Int .empty

def price : LeanRx.Field Pricing Int := .here
def quantity : LeanRx.Field Pricing Int := .there .here
def threshold : LeanRx.Field Pricing Int := .there (.there .here)

def subtotal := LeanRx.RxExpr.binary .intMul
  (LeanRx.RxExpr.read price) (LeanRx.RxExpr.read quantity)

def isLarge := LeanRx.RxExpr.binary .intLt
  (LeanRx.RxExpr.read threshold) subtotal

def label := LeanRx.RxExpr.ifThenElse isLarge
  (LeanRx.RxExpr.literal (.string "large"))
  (LeanRx.RxExpr.literal (.string "small"))

def run : IO Unit := do
  unless subtotal.dependencies.ids == [0, 1] do
    throw <| IO.userError s!"subtotal dependencies incomplete: {subtotal.dependencies.ids}"
  unless isLarge.dependencies.ids == [0, 1, 2] do
    throw <| IO.userError s!"comparison dependencies incomplete: {isLarge.dependencies.ids}"
  unless label.dependencies.ids == [0, 1, 2] do
    throw <| IO.userError "if dependencies omitted a condition or branch"
  unless label.debug ==
      "if(Int.lt(read(threshold@2),Int.mul(read(price@0),read(quantity@1))),string(large),string(small))" do
    throw <| IO.userError s!"expression debug form changed: {label.debug}"

end LeanRxTest.Expr
