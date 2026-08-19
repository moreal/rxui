import LeanRx.Graph.Model

namespace LeanRx.Graph

private def duplicateName? (specs : List NodeSpec) : Option String :=
  let rec loop (seen : List String) : List NodeSpec → Option String
    | [] => none
    | spec :: rest =>
        if seen.contains spec.name then some spec.name
        else loop (spec.name :: seen) rest
  loop [] specs

private def mkError (code message : String) (spec : NodeSpec)
    (path : Array String := #[]) : GraphError :=
  { code, message, path, spans := #[spec.span] }

private def validateShape (spec : NodeSpec) : Except GraphError Unit := do
  if spec.name.isEmpty then
    throw <| mkError "LRX-GRAPH-002" "graph node name must not be empty" spec
  if ¬(spec.deps.toList.map (·.id)).Nodup then
    throw <| mkError "LRX-GRAPH-003" "graph node has a duplicate direct dependency" spec
  match spec.kind, spec.equality with
  | .source, none =>
      unless spec.deps.isEmpty do
        throw <| mkError "LRX-GRAPH-004" "source nodes cannot have dependencies" spec
      unless spec.evaluator.isEmpty do
        throw <| mkError "LRX-GRAPH-013" "source nodes cannot have evaluators" spec
  | .source, some _ =>
      throw <| mkError "LRX-GRAPH-005" "source equality belongs to the state field contract" spec
  | .derived, none =>
      throw <| mkError "LRX-TYPE-004" "derived nodes require a lawful equality plan" spec
  | .derived, some equality =>
      unless equality == spec.valueType.equalityPlan do
        throw <| mkError "LRX-TYPE-006"
          "derived equality plan is incompatible with its runtime type" spec
      if spec.evaluator.isEmpty then
        throw <| mkError "LRX-GRAPH-006" "derived node has no evaluator" spec
  | .sink, some _ =>
      throw <| mkError "LRX-GRAPH-007" "sink nodes do not cache equality values" spec
  | .sink, none =>
      if spec.evaluator.isEmpty then
        throw <| mkError "LRX-GRAPH-008" "sink node has no evaluator" spec

private def validateRefs (specs : Array NodeSpec) (owner : NodeSpec) :
    List TypedNodeRef → Except GraphError Unit
  | [] => pure ()
  | reference :: rest => do
      let dependency ← match specs[reference.id.value]? with
        | some dependency => pure dependency
        | none => throw {
            code := "LRX-GRAPH-009"
            message := s!"dependency id {reference.id.value} is outside the graph"
            path := #[owner.name, s!"#{reference.id.value}"]
            spans := #[owner.span]
          }
      if dependency.kind == .sink then
        throw {
          code := "LRX-GRAPH-012"
          message := "sink nodes cannot be reactive dependencies"
          path := #[owner.name, dependency.name]
          spans := #[owner.span, dependency.span]
        }
      unless dependency.valueType == reference.valueType do
        throw {
          code := "LRX-TYPE-005"
          message := s!"dependency type mismatch: expected {repr reference.valueType}, found {repr dependency.valueType}"
          path := #[owner.name, dependency.name]
          spans := #[owner.span, dependency.span]
        }
      validateRefs specs owner rest

private def buildLoop (specs : Array NodeSpec) :
    List NodeSpec → Nat → List Node → Except GraphError (Array Node)
  | [], _, acc => pure acc.reverse.toArray
  | spec :: rest, id, acc => do
      validateShape spec
      validateRefs specs spec spec.deps.toList
      let node : Node :=
        { id := ⟨id⟩
          name := spec.name
          kind := spec.kind
          valueType := spec.valueType
          deps := spec.deps.map (·.id)
          rank := 0
          equality := spec.equality
          evaluator := spec.evaluator
          span := spec.span }
      buildLoop specs rest (id + 1) (node :: acc)

/-- Validate node shapes/references and assign stable declaration-order IDs. -/
def buildNodes (specs : Array NodeSpec) : Except GraphError (Array Node) := do
  if specs.isEmpty then
    throw { code := "LRX-GRAPH-010", message := "graph must contain at least one node" }
  if let some name := duplicateName? specs.toList then
    throw {
      code := "LRX-GRAPH-011"
      message := s!"duplicate graph node name: {name}"
      path := #[name]
      spans := specs.filter (·.name == name) |>.map (·.span)
    }
  buildLoop specs specs.toList 0 []

end LeanRx.Graph
