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

private def htmlChar : Char → String
  | '&' => "&amp;"
  | '<' => "&lt;"
  | '>' => "&gt;"
  | '"' => "&quot;"
  | '\'' => "&#39;"
  | char => char.toString

/-- Escape untrusted graph metadata for HTML text and quoted attributes. -/
def htmlText (value : String) : String :=
  String.join (value.toList.map htmlChar)

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

private def htmlNode (node : Node) : String :=
  let deps := if node.deps.isEmpty then "none" else
    String.intercalate ", " (node.deps.toList.map fun id => s!"n{id.value}")
  let equality := node.equality.map GraphSerialize.equality |>.getD "none"
  let source := if node.span.file.isEmpty then "&lt;generated&gt;" else
    htmlText s!"{node.span.file}:{node.span.start.line}:{node.span.start.column}"
  "<li class=\"leanrx-node leanrx-node--" ++ nodeKind node.kind ++
    "\" data-node-id=\"" ++ toString node.id.value ++ "\">" ++
    "<h2>n" ++ toString node.id.value ++ " · " ++ htmlText node.name ++ "</h2>" ++
    "<dl><dt>Kind</dt><dd>" ++ nodeKind node.kind ++
    "</dd><dt>Runtime type</dt><dd>" ++ htmlText (runtimeType node.valueType) ++
    "</dd><dt>Dependencies</dt><dd>" ++ deps ++
    "</dd><dt>Rank</dt><dd>" ++ toString node.rank ++
    "</dd><dt>Equality</dt><dd>" ++ htmlText equality ++
    "</dd><dt>Evaluator</dt><dd>" ++ htmlText node.evaluator ++
    "</dd><dt>Source</dt><dd>" ++ source ++ "</dd></dl></li>"

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

/-- Self-contained, script-free, accessible HTML graph inspection artifact. -/
def toHtml (planned : PlannedGraph) : String :=
  let nodes := String.join (planned.graph.nodes.toList.map GraphSerialize.htmlNode)
  let schedule := String.intercalate " → " <|
    planned.schedule.order.toList.map fun id => s!"n{id.value}"
  "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">" ++
    "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">" ++
    "<title>LeanRx reactive graph</title><style>" ++
    "body{font-family:system-ui,sans-serif;max-width:72rem;margin:auto;padding:2rem}" ++
    ".leanrx-schedule{font-family:ui-monospace,monospace;overflow-wrap:anywhere}" ++
    ".leanrx-nodes{display:grid;grid-template-columns:repeat(auto-fit,minmax(16rem,1fr));gap:1rem;padding:0}" ++
    ".leanrx-node{list-style:none;border:1px solid #888;border-radius:.5rem;padding:1rem}" ++
    ".leanrx-node h2{font-size:1rem;margin-top:0}.leanrx-node dl{margin:0}" ++
    ".leanrx-node dt{font-weight:700}.leanrx-node dd{margin:0 0 .5rem}</style></head>" ++
    "<body><main><h1>LeanRx reactive graph</h1><p class=\"leanrx-schedule\">" ++
    "<strong>Certified schedule:</strong> " ++
    schedule ++ "</p><ol class=\"leanrx-nodes\">" ++ nodes ++ "</ol></main></body></html>"

end PlannedGraph

end LeanRx
