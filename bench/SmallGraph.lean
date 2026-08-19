import examples.DiamondLab
import examples.GraphFixtures

namespace LeanRxBench.SmallGraph

open LeanRx LeanRxExamples.DiamondLab

private def planned : IO CheckedIntProgram :=
  match Graph.planInt intSpec with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"small graph planning failed: {error.code}"

def run (iterations : Nat) : IO Unit := do
  let checked ← planned
  let initial := Abstract.Reference.initState checked.program fun id =>
    if id = 0 then 1 else 0
  let sample := Abstract.SourceWrite.mk 0 3 :: []
  let reference := Abstract.Reference.run checked.program initial sample
  let optimized := Abstract.Optimized.run checked.program initial sample
  unless reference.observations == optimized.observations && optimized.store 3 == 19 do
    throw <| IO.userError "small graph benchmark correctness baseline failed"
  let start ← IO.monoNanosNow
  let mut state := initial
  let mut derivedEvaluations := 0
  let mut sinkEvaluations := 0
  for index in List.range iterations do
    let value := if index % 2 == 0 then 3 else 1
    let result := Abstract.Optimized.run checked.program state
      [Abstract.SourceWrite.mk 0 value]
    state := result.nextState
    derivedEvaluations := derivedEvaluations + result.derivedEvaluations
    sinkEvaluations := sinkEvaluations + result.sinkEvaluations
  let elapsed ← IO.monoNanosNow
  let parityChecked ← match Graph.planInt LeanRxExamples.GraphLab.paritySpec with
    | .ok value => pure value
    | .error error => throw <| IO.userError s!"suppression planning failed: {error.code}"
  let parityInitial := Abstract.Reference.initState parityChecked.program fun id =>
    if id = 0 then 1 else 0
  let parityWrite := [Abstract.SourceWrite.mk 0 3]
  let parityReference := Abstract.Reference.run parityChecked.program parityInitial parityWrite
  let parityOptimized := Abstract.Optimized.run parityChecked.program parityInitial parityWrite
  let referenceWork := parityReference.derivedEvaluations + parityReference.sinkEvaluations
  let optimizedWork := parityOptimized.derivedEvaluations + parityOptimized.sinkEvaluations
  unless parityReference.observations == parityOptimized.observations &&
      referenceWork == 4 && optimizedWork == 1 do
    throw <| IO.userError "small graph benchmark work-suppression baseline failed"
  IO.println <| s!"small-graph iterations={iterations} derived={derivedEvaluations} " ++
    s!"sinks={sinkEvaluations} suppressionReference={referenceWork} " ++
    s!"suppressionOptimized={optimizedWork} elapsedNs={elapsed - start}"

end LeanRxBench.SmallGraph

def main (args : List String) : IO Unit := do
  let values := match args with
    | "--" :: rest => rest
    | _ => args
  let iterations ← match values with
    | value :: _ => match value.toNat? with
      | some iterations => pure iterations
      | none => throw <| IO.userError "benchmark iterations must be a natural number"
    | [] => pure 10000
  LeanRxBench.SmallGraph.run iterations
