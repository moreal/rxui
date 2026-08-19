import Lean
import LeanRx.Graph.Serialize
import Test.Graph.Build

namespace LeanRxTest.Graph.Serialize

private def plan (specs : Array LeanRx.NodeSpec) : IO LeanRx.PlannedGraph :=
  match LeanRx.Graph.plan specs with
  | .ok planned => pure planned
  | .error error => throw <| IO.userError s!"serialization fixture failed: {error.code}"

def run : IO Unit := do
  let first ← plan LeanRxTest.Graph.Build.validSpecs
  let second ← plan LeanRxTest.Graph.Build.validSpecs
  unless first.toJson == second.toJson && first.toDot == second.toDot do
    throw <| IO.userError "repeated graph serialization was not byte deterministic"
  let expectedJson :=
    "{\"nodes\":[{\"id\":0,\"name\":\"count\",\"kind\":\"source\",\"valueType\":\"int\"," ++
    "\"deps\":[],\"rank\":0,\"equality\":null,\"evaluator\":\"\",\"span\":{\"file\":\"\"," ++
    "\"start\":{\"line\":0,\"column\":0,\"byteOffset\":0}," ++
    "\"stop\":{\"line\":0,\"column\":0,\"byteOffset\":0}}}," ++
    "{\"id\":1,\"name\":\"doubled\",\"kind\":\"derived\",\"valueType\":\"int\"," ++
    "\"deps\":[0],\"rank\":1,\"equality\":\"bigint\",\"evaluator\":\"double\"," ++
    "\"span\":{\"file\":\"\",\"start\":{\"line\":0,\"column\":0,\"byteOffset\":0}," ++
    "\"stop\":{\"line\":0,\"column\":0,\"byteOffset\":0}}}," ++
    "{\"id\":2,\"name\":\"text\",\"kind\":\"sink\",\"valueType\":\"string\"," ++
    "\"deps\":[1],\"rank\":2,\"equality\":null,\"evaluator\":\"renderText\"," ++
    "\"span\":{\"file\":\"\",\"start\":{\"line\":0,\"column\":0,\"byteOffset\":0}," ++
    "\"stop\":{\"line\":0,\"column\":0,\"byteOffset\":0}}}],\"schedule\":[0,1,2]}"
  unless first.toJson == expectedJson do
    throw <| IO.userError s!"JSON golden changed:\n{first.toJson}"
  let expectedDot := String.intercalate "\n" [
    "digraph LeanRx {",
    "  rankdir=LR;",
    "  n0 [label=\"count\\nsource\\nrank 0\"];",
    "  n1 [label=\"doubled\\nderived\\nrank 1\"];",
    "  n2 [label=\"text\\nsink\\nrank 2\"];",
    "  n0 -> n1;",
    "  n1 -> n2;",
    "}"
  ]
  unless first.toDot == expectedDot do
    throw <| IO.userError s!"DOT golden changed:\n{first.toDot}"
  let hostile ← plan #[
    .source "count\"\\\n" .int,
    .sink "</script>\nnext" .string #[{ id := ⟨0⟩, valueType := .int }] "line\n\t\"\\"
  ]
  let hostileJson := hostile.toJson
  let hostileDot := hostile.toDot
  unless hostileJson.contains "count\\\"\\\\\\n" &&
      hostileJson.contains "line\\n\\t\\\"\\\\" do
    throw <| IO.userError s!"JSON graph text was not escaped: {hostileJson}"
  unless hostileDot.contains "</script>\\nnext\\nsink" do
    throw <| IO.userError s!"DOT graph label was not escaped: {hostileDot}"
  match Lean.Json.parse hostileJson with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"graph JSON was invalid: {error}"

end LeanRxTest.Graph.Serialize
