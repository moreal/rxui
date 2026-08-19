import LeanRx

namespace LeanRxExamples.GraphLab

open LeanRx
open LeanRx.Abstract

abbrev DiamondSchema : Schema :=
  .field "count" Int <| .field "left" Int <| .field "right" Int <|
    .field "total" Int .empty

def count : Field DiamondSchema Int := .here
def left : Field DiamondSchema Int := .there .here
def right : Field DiamondSchema Int := .there (.there .here)
def total : Field DiamondSchema Int := .there (.there (.there .here))

def diamondAllInt : AllInt DiamondSchema :=
  .field (.field (.field (.field .empty)))

def leftExpr := RxExpr.binary .intAdd
  (RxExpr.read count) (RxExpr.literal (.int 10))
def rightExpr := RxExpr.binary .intMul
  (RxExpr.read count) (RxExpr.literal (.int 2))
def totalExpr := RxExpr.binary .intAdd (RxExpr.read left) (RxExpr.read right)

def diamondSpec : IntProgramSpec DiamondSchema :=
  { allInt := diamondAllInt
    sourceCount := 1
    values :=
      [ .source count
      , .derived left leftExpr
      , .derived right rightExpr
      , .derived total totalExpr
      ]
    sinks := [.observe "totalText" (RxExpr.read total)] }

abbrev ParitySchema : Schema :=
  .field "count" Int <| .field "parity" Int <| .field "downstream" Int .empty

def parityCount : Field ParitySchema Int := .here
def parity : Field ParitySchema Int := .there .here
def downstream : Field ParitySchema Int := .there (.there .here)

def parityAllInt : AllInt ParitySchema :=
  .field (.field (.field .empty))

def parityExpr := RxExpr.binary .intMod
  (RxExpr.read parityCount) (RxExpr.literal (.int 2))
def downstreamExpr := RxExpr.binary .intAdd
  (RxExpr.read parity) (RxExpr.literal (.int 100))

def paritySpec : IntProgramSpec ParitySchema :=
  { allInt := parityAllInt
    sourceCount := 1
    values :=
      [ .source parityCount
      , .derived parity parityExpr
      , .derived downstream downstreamExpr
      ]
    sinks :=
      [ .observe "paritySink" (RxExpr.read parity)
      , .observe "downstreamSink" (RxExpr.read downstream)
      ] }

private def depsText (node : Node) : String :=
  "[" ++ String.intercalate "," (node.deps.toList.map fun id => toString id.value) ++ "]"

private def nodeLine (node : Node) : String :=
  s!"node {node.id.value} {node.name} {GraphSerialize.nodeKind node.kind} " ++
    s!"rank={node.rank} deps={depsText node}"

private def edgeLines (node : Node) : List String :=
  node.deps.toList.map fun dependency => s!"edge {dependency.value}->{node.id.value}"

private def mustPlan (spec : IntProgramSpec Γ) : IO CheckedIntProgram :=
  match Graph.planInt spec with
  | .ok checked => pure checked
  | .error error => throw <| IO.userError s!"Graph Lab planning failed: {error.code}"

def run : IO Unit := do
  let diamond ← mustPlan diamondSpec
  let planned := diamond.planned
  let diamondOld := Reference.initState diamond.program fun id => if id = 0 then 1 else 0
  let graphLines := planned.graph.nodes.toList.map nodeLine ++
    planned.graph.nodes.toList.flatMap edgeLines
  IO.println <| String.intercalate "\n" graphLines

  let transaction : SourceTransaction := [{ id := 0, value := 3 }]
  let reference := Reference.run diamond.program diamondOld transaction
  let optimized := Optimized.run diamond.program diamondOld transaction
  unless reference.store 3 == 19 && reference.observations == [19] do
    throw <| IO.userError "Graph Lab reference result changed"
  unless optimized.store 3 == reference.store 3 &&
      optimized.observations == reference.observations do
    throw <| IO.userError "Graph Lab optimized result disagrees with reference"
  IO.println s!"reference total={reference.store 3} derived={reference.derivedEvaluations} sinks={reference.sinkEvaluations}"
  IO.println s!"optimized total={optimized.store 3} derived={optimized.derivedEvaluations} sinks={optimized.sinkEvaluations}"

  let parityPlan ← mustPlan paritySpec
  let parityOld := Reference.initState parityPlan.program fun id => if id = 0 then 1 else 0
  let parityTransaction : SourceTransaction := [{ id := 0, value := 3 }]
  let parityReference := Reference.run parityPlan.program parityOld parityTransaction
  let parityOptimized := Optimized.run parityPlan.program parityOld parityTransaction
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
