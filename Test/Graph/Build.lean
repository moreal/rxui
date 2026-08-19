import LeanRx.Graph.Build

namespace LeanRxTest.Graph.Build

def validSpecs : Array LeanRx.NodeSpec := #[
  .source "count" .int,
  .derived "doubled" .int #[{ id := ⟨0⟩, valueType := .int }] "double",
  .sink "text" .string #[{ id := ⟨1⟩, valueType := .int }] "renderText"
]

private def expectError (expected : String)
    (result : Except LeanRx.GraphError (Array LeanRx.Node)) : IO Unit :=
  match result with
  | .error error =>
      unless error.code == expected do
        throw <| IO.userError s!"expected {expected}, got {error.code}"
  | .ok _ => throw <| IO.userError s!"expected graph error {expected}"

private def sourceSpan (file : String) (line offset : Nat) : LeanRx.SourceSpan :=
  { file
    start := { line, column := 1, byteOffset := offset }
    stop := { line, column := 2, byteOffset := offset + 1 } }

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
    .derived "bad" .int #[{ id := ⟨9⟩, valueType := .int }] "bad"
  ]
  expectError "LRX-TYPE-005" <| LeanRx.Graph.buildNodes #[
    .source "count" .int,
    .derived "bad" .int #[{ id := ⟨0⟩, valueType := .string }] "bad"
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
    .sink "firstSink" .string #[{ id := ⟨0⟩, valueType := .int }] "first",
    .sink "secondSink" .string #[{ id := ⟨1⟩, valueType := .string }] "second"
  ]
  for (valueType, equality) in [
      (.bool, .bigint), (.string, .bigint), (.int, .strict), (.nat, .structural)
    ] do
    expectError "LRX-TYPE-006" <| LeanRx.Graph.buildNodes #[
      { name := "badEquality", kind := .derived, valueType, deps := #[],
        equality := some equality, evaluator := "bad", span := .generated }
    ]
  expectError "LRX-GRAPH-013" <| LeanRx.Graph.buildNodes #[
    { name := "badSource", kind := .source, valueType := .int, deps := #[],
      equality := none, evaluator := "unexpected", span := .generated }
  ]
  expectError "LRX-GRAPH-002" <| LeanRx.Graph.buildNodes #[.source "" .int]
  expectError "LRX-GRAPH-003" <| LeanRx.Graph.buildNodes #[
    .source "count" .int,
    .derived "duplicateDeps" .int #[
      { id := ⟨0⟩, valueType := .int }, { id := ⟨0⟩, valueType := .int }
    ] "bad"
  ]
  expectError "LRX-GRAPH-005" <| LeanRx.Graph.buildNodes #[
    { name := "source", kind := .source, valueType := .int, deps := #[],
      equality := some .bigint, evaluator := "", span := .generated }
  ]
  expectError "LRX-TYPE-004" <| LeanRx.Graph.buildNodes #[
    { name := "derived", kind := .derived, valueType := .int, deps := #[],
      equality := none, evaluator := "value", span := .generated }
  ]
  expectError "LRX-GRAPH-006" <| LeanRx.Graph.buildNodes #[
    { name := "derived", kind := .derived, valueType := .int, deps := #[],
      equality := some .bigint, evaluator := "", span := .generated }
  ]
  expectError "LRX-GRAPH-007" <| LeanRx.Graph.buildNodes #[
    { name := "sink", kind := .sink, valueType := .string, deps := #[],
      equality := some .strict, evaluator := "sink", span := .generated }
  ]
  expectError "LRX-GRAPH-008" <| LeanRx.Graph.buildNodes #[
    { name := "sink", kind := .sink, valueType := .string, deps := #[],
      equality := none, evaluator := "", span := .generated }
  ]
  expectError "LRX-GRAPH-010" <| LeanRx.Graph.buildNodes #[]
  let sourceLocation := sourceSpan "app/Main.lean" 2 10
  let consumerLocation := sourceSpan "app/Main.lean" 4 30
  match LeanRx.Graph.buildNodes #[
      .source "typed" .int sourceLocation,
      .derived "consumer" .int #[{ id := ⟨0⟩, valueType := .string }]
        "consumer" consumerLocation
    ] with
  | .ok _ => throw <| IO.userError "source-linked type mismatch unexpectedly passed"
  | .error error =>
      unless error.code == "LRX-TYPE-005" && error.path == #["consumer", "typed"] &&
          error.spans == #[consumerLocation, sourceLocation] &&
          error.message.startsWith "dependency type mismatch" do
        throw <| IO.userError "type mismatch lost its path, message, or source spans"
  let firstDuplicate := sourceSpan "app/Main.lean" 6 50
  let secondDuplicate := sourceSpan "app/Main.lean" 8 70
  match LeanRx.Graph.buildNodes #[
      .source "duplicate" .int firstDuplicate,
      .source "duplicate" .int secondDuplicate
    ] with
  | .ok _ => throw <| IO.userError "source-linked duplicate name unexpectedly passed"
  | .error error =>
      unless error.code == "LRX-GRAPH-011" && error.path == #["duplicate"] &&
          error.spans == #[firstDuplicate, secondDuplicate] do
        throw <| IO.userError "duplicate name lost declaration spans"

end LeanRxTest.Graph.Build
