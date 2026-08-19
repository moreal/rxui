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

def pricingStore (priceValue quantityValue thresholdValue : Int) : LeanRx.Store Pricing :=
  .cons priceValue <| .cons quantityValue <| .cons thresholdValue .empty

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
  unless subtotal.eval (pricingStore 12 4 40) == 48 do
    throw <| IO.userError "native expression multiplication is incorrect"
  unless label.eval (pricingStore 12 4 40) == "large" do
    throw <| IO.userError "native expression condition selected the wrong branch"
  unless label.eval (pricingStore 5 4 40) == "small" do
    throw <| IO.userError "native expression false branch is incorrect"
  let unicode := LeanRx.RxExpr.binary .stringAppend
    (LeanRx.RxExpr.literal (.string "린"))
    (LeanRx.RxExpr.literal (.string "리액스"))
  unless unicode.eval (.empty : LeanRx.Store .empty) == "린리액스" do
    throw <| IO.userError "Unicode string append changed native semantics"
  let huge := LeanRx.RxExpr.binary .intAdd
    (LeanRx.RxExpr.literal (.int 9007199254740993))
    (LeanRx.RxExpr.literal (.int 9))
  unless huge.eval (.empty : LeanRx.Store .empty) == 9007199254741002 do
    throw <| IO.userError "native Int evaluation lost unbounded semantics"

end LeanRxTest.Expr
