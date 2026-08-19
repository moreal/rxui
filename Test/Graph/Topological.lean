import LeanRx.Graph.Topological
import Test.Graph.Build

namespace LeanRxTest.Graph.Topological

private def mustPlan (specs : Array LeanRx.NodeSpec) : IO LeanRx.PlannedGraph :=
  match LeanRx.Graph.plan specs with
  | .ok planned => pure planned
  | .error error => throw <| IO.userError s!"planning failed: {error.code} {error.path.toList}"

private def expectCycle (expected : Array String) (specs : Array LeanRx.NodeSpec) : IO Unit :=
  match LeanRx.Graph.plan specs with
  | .ok _ => throw <| IO.userError "cycle unexpectedly produced a schedule"
  | .error error =>
      unless error.code == "LRX-GRAPH-001" && error.path == expected do
        throw <| IO.userError s!"cycle path is not useful: {error.path.toList}"

def run : IO Unit := do
  let linear ← mustPlan LeanRxTest.Graph.Build.validSpecs
  unless linear.schedule.order.map (·.value) == #[0, 1, 2] do
    throw <| IO.userError "linear topological order changed"
  unless linear.graph.nodes.map (·.rank) == #[0, 1, 2] do
    throw <| IO.userError "linear ranks changed"
  let diamond ← mustPlan #[
    .source "source" .int,
    .derived "left" .int #[{ id := ⟨0⟩, valueType := .int }] .bigint "left",
    .derived "right" .int #[{ id := ⟨0⟩, valueType := .int }] .bigint "right",
    .derived "join" .int #[{ id := ⟨1⟩, valueType := .int }, { id := ⟨2⟩, valueType := .int }]
      .bigint "join",
    .sink "sink" #[{ id := ⟨3⟩, valueType := .int }] "sink"
  ]
  unless diamond.schedule.order.map (·.value) == #[0, 1, 2, 3, 4] do
    throw <| IO.userError "diamond schedule is not deterministic"
  unless diamond.graph.nodes.map (·.rank) == #[0, 1, 1, 2, 3] do
    throw <| IO.userError "diamond ranks do not preserve fan-in"
  let fanOut ← mustPlan #[
    .source "source" .int,
    .derived "left" .int #[{ id := ⟨0⟩, valueType := .int }] .bigint "left",
    .derived "right" .int #[{ id := ⟨0⟩, valueType := .int }] .bigint "right"
  ]
  unless fanOut.graph.nodes.map (·.rank) == #[0, 1, 1] do
    throw <| IO.userError "fan-out ranks changed"
  let fanIn ← mustPlan #[
    .source "left" .int,
    .source "right" .int,
    .derived "join" .int #[{ id := ⟨0⟩, valueType := .int }, { id := ⟨1⟩, valueType := .int }]
      .bigint "join"
  ]
  unless fanIn.graph.nodes.map (·.rank) == #[0, 0, 1] do
    throw <| IO.userError "fan-in ranks changed"
  let disconnected ← mustPlan #[
    .source "firstSource" .int,
    .source "secondSource" .int,
    .derived "firstDerived" .int #[{ id := ⟨0⟩, valueType := .int }] .bigint "first",
    .derived "secondDerived" .int #[{ id := ⟨1⟩, valueType := .int }] .bigint "second"
  ]
  unless disconnected.schedule.order.map (·.value) == #[0, 1, 2, 3] &&
      disconnected.graph.nodes.map (·.rank) == #[0, 0, 1, 1] do
    throw <| IO.userError "disconnected component schedule changed"
  let sourceOnly ← mustPlan #[.source "unused" .int]
  unless sourceOnly.schedule.order.map (·.value) == #[0] do
    throw <| IO.userError "source without consumers was not scheduled"
  expectCycle #["a", "b", "a"] #[
    .source "source" .int,
    .derived "a" .int #[{ id := ⟨2⟩, valueType := .int }] .bigint "a",
    .derived "b" .int #[{ id := ⟨1⟩, valueType := .int }] .bigint "b"
  ]
  expectCycle #["a", "c", "b", "a"] #[
    .source "source" .int,
    .derived "a" .int #[{ id := ⟨3⟩, valueType := .int }] .bigint "a",
    .derived "b" .int #[{ id := ⟨1⟩, valueType := .int }] .bigint "b",
    .derived "c" .int #[{ id := ⟨2⟩, valueType := .int }] .bigint "c"
  ]

end LeanRxTest.Graph.Topological
