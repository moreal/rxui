import LeanRx

namespace LeanRxExamples.ExpressionPlayground

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
  (LeanRx.RxExpr.literal (.string "large order"))
  (LeanRx.RxExpr.literal (.string "small order"))

def store (priceValue quantityValue thresholdValue : Int) : LeanRx.Store Pricing :=
  .cons priceValue <| .cons quantityValue <| .cons thresholdValue .empty

def report (name : String) (values : LeanRx.Store Pricing) : List String :=
  [ s!"{name} subtotal: {subtotal.eval values}"
  , s!"{name} isLarge: {isLarge.eval values}"
  , s!"{name} label: {label.eval values}"
  ]

def run : IO Unit := do
  IO.println s!"subtotal deps: {subtotal.dependencies.debug}"
  IO.println s!"isLarge deps: {isLarge.dependencies.debug}"
  IO.println s!"label deps: {label.dependencies.debug}"
  for line in report "first" (store 12 4 40) do
    IO.println line
  for line in report "second" (store 5 4 40) do
    IO.println line

end LeanRxExamples.ExpressionPlayground

def main : IO Unit :=
  LeanRxExamples.ExpressionPlayground.run
