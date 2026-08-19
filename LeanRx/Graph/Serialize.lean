import LeanRx.Graph.Topological

namespace LeanRx

namespace GraphSerialize

private def hexDigit : Nat → String
  | 0 => "0" | 1 => "1" | 2 => "2" | 3 => "3"
  | 4 => "4" | 5 => "5" | 6 => "6" | 7 => "7"
  | 8 => "8" | 9 => "9" | 10 => "a" | 11 => "b"
  | 12 => "c" | 13 => "d" | 14 => "e" | _ => "f"

private def escapeChar (char : Char) : String :=
  match char with
  | '"' => "\\\""
  | '\\' => "\\\\"
  | '\x08' => "\\b"
  | '\x0c' => "\\f"
  | '\n' => "\\n"
  | '\r' => "\\r"
  | '\t' => "\\t"
  | char =>
      let code := char.toNat
      if code < 32 then "\\u00" ++ hexDigit (code / 16) ++ hexDigit (code % 16)
      else char.toString

def jsonString (value : String) : String :=
  "\"" ++ String.join (value.toList.map escapeChar) ++ "\""

def nodeKind : NodeKind → String
  | .source => "source"
  | .derived => "derived"
  | .sink => "sink"

def runtimeType (value : RuntimeTypeId) : String := value.debug

def equality : JsEqPlan → String
  | .strict => "strict"
  | .bigint => "bigint"
  | .structural => "structural"

private def positionJson (position : SourcePos) : String :=
  "{\"line\":" ++ toString position.line ++
    ",\"column\":" ++ toString position.column ++
    ",\"byteOffset\":" ++ toString position.byteOffset ++ "}"

private def spanJson (span : SourceSpan) : String :=
  "{\"file\":" ++ jsonString span.file ++
    ",\"start\":" ++ positionJson span.start ++
    ",\"stop\":" ++ positionJson span.stop ++ "}"

private def natArrayJson (values : Array Nat) : String :=
  "[" ++ String.intercalate "," (values.toList.map toString) ++ "]"

private def nodeJson (node : Node) : String :=
  let equalityValue := node.equality.map (jsonString ∘ equality) |>.getD "null"
  "{\"id\":" ++ toString node.id.value ++
    ",\"name\":" ++ jsonString node.name ++
    ",\"kind\":" ++ jsonString (nodeKind node.kind) ++
    ",\"valueType\":" ++ jsonString (runtimeType node.valueType) ++
    ",\"deps\":" ++ natArrayJson (node.deps.map (·.value)) ++
    ",\"rank\":" ++ toString node.rank ++
    ",\"equality\":" ++ equalityValue ++
    ",\"evaluator\":" ++ jsonString node.evaluator ++
    ",\"span\":" ++ spanJson node.span ++ "}"

private def dotNode (node : Node) : String :=
  let deps := String.intercalate "," (node.deps.toList.map (toString ·.value))
  let equality := node.equality.map (GraphSerialize.equality) |>.getD "none"
  let source := if node.span.file.isEmpty then "<generated>" else
    s!"{node.span.file}:{node.span.start.line}:{node.span.start.column}"
  let label := s!"{node.name}\nkind={nodeKind node.kind}\nvalueType={runtimeType node.valueType}" ++
    s!"\ndeps=[{deps}]\nrank={node.rank}\nequality={equality}" ++
    s!"\nevaluator={node.evaluator}\nsource={source}"
  s!"  n{node.id.value} [label={jsonString label}];"

private def dotEdges (node : Node) : List String :=
  node.deps.toList.map fun dependency =>
    s!"  n{dependency.value} -> n{node.id.value};"

end GraphSerialize

namespace PlannedGraph

/-- Compact deterministic graph manifest. Array order is declaration/schedule order. -/
def toJson (planned : PlannedGraph) : String :=
  let nodes := String.intercalate "," <|
    planned.graph.nodes.toList.map GraphSerialize.nodeJson
  let schedule := planned.schedule.order.map (·.value)
  "{\"nodes\":[" ++ nodes ++ "],\"schedule\":" ++
    GraphSerialize.natArrayJson schedule ++ "}"

/-- Deterministic DOT graph with escaped labels and declaration-ordered edges. -/
def toDot (planned : PlannedGraph) : String :=
  let nodes := planned.graph.nodes.toList.map GraphSerialize.dotNode
  let edges := planned.graph.nodes.toList.flatMap GraphSerialize.dotEdges
  String.intercalate "\n" (["digraph LeanRx {", "  rankdir=LR;"] ++ nodes ++ edges ++ ["}"])

end PlannedGraph

end LeanRx
