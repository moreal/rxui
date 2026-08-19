import LeanRx.Core.Schema

namespace LeanRxTest.Schema

abbrev Cart : LeanRx.Schema :=
  .field "price" Int <| .field "quantity" Nat <| .field "featured" Bool .empty

def price : LeanRx.Field Cart Int := .here
def quantity : LeanRx.Field Cart Nat := .there .here
def featured : LeanRx.Field Cart Bool := .there (.there .here)

def run : IO Unit := do
  unless Cart.size == 3 do
    throw <| IO.userError "schema size is not declaration-stable"
  unless Cart.names == ["price", "quantity", "featured"] do
    throw <| IO.userError "schema names are not in declaration order"
  unless price.index == 0 && quantity.index == 1 && featured.index == 2 do
    throw <| IO.userError "typed field indices are not declaration-stable"
  unless price.name == "price" && quantity.name == "quantity" && featured.name == "featured" do
    throw <| IO.userError "typed fields lost their names"

end LeanRxTest.Schema
