import examples.DiamondLab

namespace LeanRxTest.Component.DiamondLab

open LeanRx LeanRxExamples.DiamondLab

def run : IO Unit := do
  match DiamondSyntax_check with
  | .error error => throw <| IO.userError s!"Diamond component rejected: {error.code}"
  | .ok checked =>
    unless checked.graph.graph.nodes.map (·.name) ==
        #["count", "left", "right", "total", "leftText", "rightText", "totalText"] &&
        checked.graph.graph.nodes.map (·.rank) == #[0, 1, 1, 2, 2, 2, 3] do
      throw <| IO.userError "Diamond component graph shape changed"
  let proofProgram ← match Graph.planInt intSpec with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"Diamond proof adapter failed: {error.code}"
  let initial := Abstract.Reference.initState proofProgram.program fun id =>
    if id = 0 then 1 else 0
  let reference := Abstract.Reference.run proofProgram.program initial abstractTransaction
  let optimized := Abstract.Optimized.run proofProgram.program initial abstractTransaction
  unless reference.store 3 == 19 && optimized.store 3 == 19 &&
      reference.observations == optimized.observations &&
      optimized.derivedEvaluations == 3 && optimized.sinkEvaluations == 1 do
    throw <| IO.userError "Diamond native semantics or instrumentation changed"

end LeanRxTest.Component.DiamondLab
