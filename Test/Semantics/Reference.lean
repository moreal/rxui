import Test.Semantics.Fixtures

namespace LeanRxTest.Semantics.Reference

def run : IO Unit := do
  let result := LeanRx.Abstract.Reference.run
    LeanRxTest.Semantics.Fixtures.diamondProgram
    LeanRxTest.Semantics.Fixtures.oldState
    LeanRxTest.Semantics.Fixtures.countToThree
  unless result.store 1 == 13 && result.store 2 == 6 && result.store 3 == 19 do
    throw <| IO.userError "reference evaluator did not recompute diamond order"
  unless result.observations == [19] do
    throw <| IO.userError "reference evaluator produced wrong sink observation"
  unless result.derivedEvaluations == 3 && result.sinkEvaluations == 1 do
    throw <| IO.userError "reference evaluator counts are not full recomputation"

end LeanRxTest.Semantics.Reference
