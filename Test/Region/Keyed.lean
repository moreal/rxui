import LeanRx.Region.Keyed

namespace LeanRxTest.Region.Keyed

open LeanRx.Region

private def item (key : Nat) (value : String) : KeyedItem :=
  { key, node := .text value }

private def checked (items : List KeyedItem) : IO KeyedList :=
  match KeyedList.create items with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"keyed fixture failed: {error.code}"

def run : IO Unit := do
  match KeyedList.create [item 1 "a", item 1 "duplicate"] with
  | .ok _ => throw <| IO.userError "duplicate keyed items were accepted"
  | .error error =>
      unless error.code == "LRX-REGION-001" do
        throw <| IO.userError "duplicate key diagnostic changed"
  let mounted := mountKeyed (← checked [item 1 "a", item 2 "b", item 3 "c"]) 100
  unless mounted.mounted.map (·.token) == [100, 101, 102] && mounted.created == 3 &&
      mounted.nextToken == 103 do
    throw <| IO.userError "keyed mount tokens changed"
  let reordered := reconcileKeyed mounted.mounted
    (← checked [item 3 "c", item 1 "a", item 2 "B"]) mounted.nextToken
  unless reordered.mounted.map (·.token) == [102, 100, 101] &&
      keyedLogical reordered.mounted == [item 3 "c", item 1 "a", item 2 "B"] &&
      reordered.created == 0 && reordered.disposed == [] && reordered.moved == 3 &&
      reordered.scalarUpdates == 1 do
    throw <| IO.userError "keyed reorder lost identity or direct updates"
  let replaced := reconcileKeyed reordered.mounted
    (← checked [item 3 "c", item 2 "B", item 4 "d"]) reordered.nextToken
  unless replaced.mounted.map (·.token) == [102, 101, 103] &&
      replaced.disposed == [100] && replaced.created == 1 && replaced.nextToken == 104 do
    throw <| IO.userError "keyed removal/insertion ownership changed"

end LeanRxTest.Region.Keyed
