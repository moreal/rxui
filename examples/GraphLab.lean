import LeanRx

namespace LeanRxExamples.GraphLab

open LeanRx
open LeanRx.Abstract

def diamondSpecs : Array NodeSpec := #[
  .source "count" .int,
  .derived "left" .int #[{ id := ⟨0⟩, valueType := .int }] "count + 10",
  .derived "right" .int #[{ id := ⟨0⟩, valueType := .int }] "count * 2",
  .derived "total" .int #[{ id := ⟨1⟩, valueType := .int }, { id := ⟨2⟩, valueType := .int }]
    "left + right",
  .sink "totalText" #[{ id := ⟨3⟩, valueType := .int }] "observe total"
]

def diamondProgram : Program :=
  { sourceCount := 1
    derived :=
      [ { id := 1, evaluator := .map 0 (· + 10) }
      , { id := 2, evaluator := .map 0 (· * 2) }
      , { id := 3, evaluator := .map₂ 1 2 (· + ·) }
      ]
    sinks := [{ name := "total", evaluator := .map 3 (fun value => value) }] }

def diamondOldStore : Store := fun id =>
  match id with
  | 0 => 1
  | 1 => 11
  | 2 => 2
  | 3 => 13
  | _ => 0

def diamondOld : State := { store := diamondOldStore, sinkCache := [13] }

def parityProgram : Program :=
  { sourceCount := 1
    derived :=
      [ { id := 1, evaluator := .map 0 (fun value => value % 2) }
      , { id := 2, evaluator := .map 1 (· + 100) }
      ]
    sinks :=
      [ { name := "parity", evaluator := .map 1 (fun value => value) }
      , { name := "downstream", evaluator := .map 2 (fun value => value) }
      ] }

def parityStore : Store := fun id =>
  match id with
  | 0 => 1
  | 1 => 1
  | 2 => 101
  | _ => 0

def parityOld : State := { store := parityStore, sinkCache := [1, 101] }

private def depsText (node : Node) : String :=
  "[" ++ String.intercalate "," (node.deps.toList.map fun id => toString id.value) ++ "]"

private def nodeLine (node : Node) : String :=
  s!"node {node.id.value} {node.name} {GraphSerialize.nodeKind node.kind} " ++
    s!"rank={node.rank} deps={depsText node}"

private def edgeLines (node : Node) : List String :=
  node.deps.toList.map fun dependency => s!"edge {dependency.value}->{node.id.value}"

def run : IO Unit := do
  let planned ← match Graph.plan diamondSpecs with
    | .ok planned => pure planned
    | .error error => throw <| IO.userError s!"Graph Lab planning failed: {error.code}"
  let graphLines := planned.graph.nodes.toList.map nodeLine ++
    planned.graph.nodes.toList.flatMap edgeLines
  IO.println <| String.intercalate "\n" graphLines

  let transaction : SourceTransaction := [{ id := 0, value := 3 }]
  let reference := Reference.run diamondProgram diamondOld transaction
  let optimized := Optimized.run diamondProgram diamondOld transaction
  unless reference.store 3 == 19 && reference.observations == [19] do
    throw <| IO.userError "Graph Lab reference result changed"
  unless optimized.store 3 == reference.store 3 &&
      optimized.observations == reference.observations do
    throw <| IO.userError "Graph Lab optimized result disagrees with reference"
  IO.println s!"reference total={reference.store 3} derived={reference.derivedEvaluations} sinks={reference.sinkEvaluations}"
  IO.println s!"optimized total={optimized.store 3} derived={optimized.derivedEvaluations} sinks={optimized.sinkEvaluations}"

  let parityTransaction : SourceTransaction := [{ id := 0, value := 3 }]
  let parityReference := Reference.run parityProgram parityOld parityTransaction
  let parityOptimized := Optimized.run parityProgram parityOld parityTransaction
  unless parityReference.observations == parityOptimized.observations do
    throw <| IO.userError "Graph Lab parity observations disagree"
  unless parityOptimized.derivedEvaluations == 1 && parityOptimized.sinkEvaluations == 0 do
    throw <| IO.userError "Graph Lab parity consumers were scheduled"
  IO.println "parity count 1->3"
  IO.println "parity odd->odd"
  IO.println <| s!"parity work reference={parityReference.derivedEvaluations + parityReference.sinkEvaluations} " ++
    s!"optimized={parityOptimized.derivedEvaluations + parityOptimized.sinkEvaluations}"

end LeanRxExamples.GraphLab

def main : IO Unit :=
  LeanRxExamples.GraphLab.run
