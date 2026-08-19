import LeanRx.Core.Dependency
import Test.Core.Schema

namespace LeanRxTest.Dependency

open LeanRxTest.Schema

def run : IO Unit := do
  let priceOnly := LeanRx.DepSet.singleton price
  let quantityOnly := LeanRx.DepSet.singleton quantity
  let featuredOnly := LeanRx.DepSet.singleton featured
  let mixed := LeanRx.DepSet.union featuredOnly <|
    LeanRx.DepSet.union priceOnly quantityOnly
  unless mixed.ids == [0, 1, 2] do
    throw <| IO.userError s!"dependency union was not canonical: {mixed.ids}"
  let duplicate := LeanRx.DepSet.union priceOnly priceOnly
  unless duplicate.ids == [0] do
    throw <| IO.userError "dependency union retained a duplicate"
  unless mixed.debug == "{0,1,2}" do
    throw <| IO.userError "dependency debug output is not stable"

example : (LeanRx.DepSet.singleton price).Contains price :=
  LeanRx.DepSet.contains_singleton price

example :
    (LeanRx.DepSet.union (LeanRx.DepSet.singleton price)
      (LeanRx.DepSet.singleton quantity)).Contains quantity :=
  LeanRx.DepSet.contains_union_right quantity _ _ <|
    LeanRx.DepSet.contains_singleton quantity

end LeanRxTest.Dependency
