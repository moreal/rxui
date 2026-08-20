import LeanRx.Region.Model

namespace LeanRxTest.Region.Conditional

open LeanRx.Region

private def paragraph (value : String) : LogicalNode :=
  .element "p" [("class", "message")] [.text value]

def run : IO Unit := do
  let mounted := mountConditional true (paragraph "ready") (paragraph "empty") 10
  unless mounted.mounted.token == 10 && mounted.mounted.node == paragraph "ready" &&
      mounted.nextToken == 11 do
    throw <| IO.userError "conditional mount identity changed"
  let scalar := reconcileConditional mounted true (paragraph "updated") (paragraph "empty")
  unless scalar.mounted.token == 10 && scalar.mounted.node == paragraph "updated" &&
      scalar.disposed == [] && scalar.replacements == 0 && scalar.scalarUpdates == 1 do
    throw <| IO.userError "stable conditional branch stopped using direct scalar update"
  let unchanged := reconcileConditional scalar true (paragraph "updated") (paragraph "empty")
  unless unchanged.mounted.token == 10 && unchanged.scalarUpdates == 0 do
    throw <| IO.userError "unchanged conditional branch performed work"
  let replaced := reconcileConditional unchanged false (paragraph "updated") (paragraph "empty")
  unless replaced.mounted.token == 11 && replaced.mounted.node == paragraph "empty" &&
      replaced.disposed == [10] && replaced.replacements == 1 &&
      replaced.scalarUpdates == 0 do
    throw <| IO.userError "conditional branch replacement/disposal changed"

end LeanRxTest.Region.Conditional
