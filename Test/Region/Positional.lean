import LeanRx.Region.Positional

namespace LeanRxTest.Region.Positional

open LeanRx.Region

private def text (value : String) : LogicalNode := .text value

def run : IO Unit := do
  let mounted := mountPositional [text "a", text "b"] 20
  unless mounted.mounted.map (·.token) == [20, 21] && mounted.nextToken == 22 &&
      mounted.created == 2 do
    throw <| IO.userError "positional mount tokens changed"
  let appended := reconcilePositional mounted.mounted [text "a", text "B", text "c"]
    mounted.nextToken
  unless appended.mounted.map (·.token) == [20, 21, 22] &&
      positionalLogical appended.mounted == [text "a", text "B", text "c"] &&
      appended.created == 1 && appended.scalarUpdates == 1 && appended.disposed == [] do
    throw <| IO.userError "positional append/update behavior changed"
  let removed := reconcilePositional appended.mounted [text "A"] appended.nextToken
  unless removed.mounted.map (·.token) == [20] &&
      positionalLogical removed.mounted == [text "A"] &&
      removed.disposed == [21, 22] && removed.created == 0 &&
      removed.scalarUpdates == 1 do
    throw <| IO.userError "positional suffix disposal changed"

end LeanRxTest.Region.Positional
