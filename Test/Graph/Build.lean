import LeanRx.Graph.Build

namespace LeanRxTest.Graph.Build

def validSpecs : Array LeanRx.NodeSpec := #[
  .source "count" .int,
  .derived "doubled" .int #[{ id := ⟨0⟩, valueType := .int }] .bigint "double",
  .sink "text" #[{ id := ⟨1⟩, valueType := .int }] "renderText"
]

private def expectError (expected : String)
    (result : Except LeanRx.GraphError (Array LeanRx.Node)) : IO Unit :=
  match result with
  | .error error =>
      unless error.code == expected do
        throw <| IO.userError s!"expected {expected}, got {error.code}"
  | .ok _ => throw <| IO.userError s!"expected graph error {expected}"

def run : IO Unit := do
  let nodes ← match LeanRx.Graph.buildNodes validSpecs with
    | .ok nodes => pure nodes
    | .error error => throw <| IO.userError s!"valid graph failed: {error.code}"
  unless nodes.map (·.id.value) == #[0, 1, 2] do
    throw <| IO.userError "stable graph IDs do not follow declaration order"
  unless nodes.map (·.deps) == #[#[], #[⟨0⟩], #[⟨1⟩]] do
    throw <| IO.userError "builder flattened or changed a direct sink dependency"
  expectError "LRX-GRAPH-009" <| LeanRx.Graph.buildNodes #[
    .source "count" .int,
    .derived "bad" .int #[{ id := ⟨9⟩, valueType := .int }] .bigint "bad"
  ]
  expectError "LRX-TYPE-005" <| LeanRx.Graph.buildNodes #[
    .source "count" .int,
    .derived "bad" .int #[{ id := ⟨0⟩, valueType := .string }] .bigint "bad"
  ]
  expectError "LRX-GRAPH-004" <| LeanRx.Graph.buildNodes #[
    { name := "source", kind := .source, valueType := .int,
      deps := #[{ id := ⟨0⟩, valueType := .int }], equality := none,
      evaluator := "", span := .generated }
  ]
  expectError "LRX-GRAPH-011" <| LeanRx.Graph.buildNodes #[
    .source "same" .int, .source "same" .int
  ]
  expectError "LRX-GRAPH-012" <| LeanRx.Graph.buildNodes #[
    .source "count" .int,
    .sink "firstSink" #[{ id := ⟨0⟩, valueType := .int }] "first",
    .sink "secondSink" #[{ id := ⟨1⟩, valueType := .string }] "second"
  ]

end LeanRxTest.Graph.Build
