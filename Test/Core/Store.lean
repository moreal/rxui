import LeanRx.Core.Store
import Test.Core.Schema

namespace LeanRxTest.Store

open LeanRxTest.Schema

def initial : LeanRx.Store Cart :=
  .cons (17 : Int) <| .cons (3 : Nat) <| .cons true .empty

abbrev UniverseOne : LeanRx.Schema.{1} := .field "storedType" Type .empty
def storedType : LeanRx.Field UniverseOne Type := .here
def typeStore : LeanRx.Store UniverseOne := .cons Nat .empty

example : typeStore.get storedType = Nat := rfl

def run : IO Unit := do
  unless initial.get price == 17 do
    throw <| IO.userError "heterogeneous store returned the wrong Int field"
  unless initial.get quantity == 3 do
    throw <| IO.userError "heterogeneous store returned the wrong Nat field"
  unless initial.get featured do
    throw <| IO.userError "heterogeneous store returned the wrong Bool field"
  let changed := initial.set quantity 9
  unless changed.get quantity == 9 && changed.get price == 17 && changed.get featured do
    throw <| IO.userError "typed store update changed the wrong slot"

example : (initial.set price 42).get price = 42 :=
  LeanRx.Store.get_set_same initial price 42

end LeanRxTest.Store
