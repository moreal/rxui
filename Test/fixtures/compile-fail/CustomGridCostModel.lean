import LeanRx

open LeanRx.Grid

def custom : Spec :=
  Spec.create "custom" (costModel := { defaultCostModel with deltaFixedCost := 1000000 })
