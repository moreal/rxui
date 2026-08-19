import LeanRx.Graph.Model

namespace LeanRxTest.Graph.Model

def run : IO Unit := do
  let count := LeanRx.NodeSpec.source "count" .int
  let doubled := LeanRx.NodeSpec.derived "doubled" .int
    #[{ id := ⟨0⟩, valueType := .int }] "double"
  let sink := LeanRx.NodeSpec.sink "text"
    #[{ id := ⟨1⟩, valueType := .int }] "renderText"
  unless count.kind == .source && count.deps.isEmpty do
    throw <| IO.userError "source node specification gained dependencies"
  unless doubled.kind == .derived && doubled.equality == some .bigint do
    throw <| IO.userError "derived node lost equality metadata"
  unless sink.kind == .sink && sink.deps.map (·.id) == #[⟨1⟩] do
    throw <| IO.userError "sink direct dependency changed"
  unless LeanRx.RuntimeRep.typeId Int == .int do
    throw <| IO.userError "runtime type erasure changed Int identity"

end LeanRxTest.Graph.Model
