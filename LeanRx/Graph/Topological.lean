import LeanRx.Graph.Build

namespace LeanRx

structure Schedule where
  order : Array NodeId
deriving Repr, BEq, DecidableEq

namespace Schedule

def position (schedule : Schedule) (id : NodeId) : Nat :=
  let rec loop (index : Nat) : List NodeId → Nat
    | [] => schedule.order.size
    | current :: rest => if current == id then index else loop (index + 1) rest
  loop 0 schedule.order.toList

def coversNodes (schedule : Schedule) (graph : Graph) : Bool :=
  graph.nodes.toList.all fun node => schedule.order.toList.contains node.id

def hasNoExtras (schedule : Schedule) (graph : Graph) : Bool :=
  schedule.order.toList.all fun id => graph.nodes.toList.any (·.id == id)

def respectsEdges (schedule : Schedule) (graph : Graph) : Bool :=
  graph.nodes.toList.all fun node =>
    node.deps.toList.all fun dep => decide (schedule.position dep < schedule.position node.id)

def Valid (schedule : Schedule) (graph : Graph) : Prop :=
  schedule.order.toList.Nodup ∧
  schedule.coversNodes graph = true ∧
  schedule.hasNoExtras graph = true ∧
  schedule.respectsEdges graph = true

instance (schedule : Schedule) (graph : Graph) : Decidable (schedule.Valid graph) :=
  inferInstanceAs <| Decidable (_ ∧ _ ∧ _ ∧ _)

end Schedule

structure PlannedGraph where
  private mk ::
  graph : Graph
  schedule : Schedule
  valid : schedule.Valid graph

namespace Graph

private def isReady (scheduled : List NodeId) (node : Node) : Bool :=
  node.deps.toList.all scheduled.contains

private def findReady? (scheduled : List NodeId) : List Node → Option Node
  | [] => none
  | node :: rest => if isReady scheduled node then some node else findReady? scheduled rest

private def rankOf (id : NodeId) : List Node → Nat
  | [] => 0
  | node :: rest => if node.id == id then node.rank else rankOf id rest

private def computeRank (ranked : List Node) (node : Node) : Nat :=
  if node.deps.isEmpty then 0
  else node.deps.toList.foldl (fun acc dep => max acc (rankOf dep ranked + 1)) 0

private def findNode? (nodes : List Node) (id : NodeId) : Option Node :=
  nodes.find? (·.id == id)

private def cycleIds (remaining : List Node) : Array NodeId :=
  let remainingIds := remaining.map (·.id)
  let rec follow (fuel : Nat) (current : NodeId) (seen : List NodeId) : List NodeId :=
    match fuel with
    | 0 => (current :: seen).reverse
    | fuel + 1 =>
        if seen.contains current then (current :: seen).reverse
        else
          match findNode? remaining current with
          | none => (current :: seen).reverse
          | some node =>
              match node.deps.toList.find? remainingIds.contains with
              | none => (current :: seen).reverse
              | some next => follow fuel next (current :: seen)
  match remaining with
  | [] => #[]
  | first :: _ => (follow (remaining.length + 1) first.id []).toArray

private def cycleError (remaining : List Node) : GraphError :=
  let ids := cycleIds remaining
  let names := ids.map fun id => (findNode? remaining id).map (·.name) |>.getD s!"#{id.value}"
  let spans := ids.filterMap fun id => (findNode? remaining id).map (·.span)
  { code := "LRX-GRAPH-001"
    message := "reactive dependency cycle"
    path := names
    spans }

private def topoLoop : Nat → List Node → List NodeId → List Node →
    Except GraphError (List NodeId × List Node)
  | 0, [], scheduled, ranked => pure (scheduled.reverse, ranked)
  | 0, remaining, _, _ => throw <| cycleError remaining
  | _ + 1, [], scheduled, ranked => pure (scheduled.reverse, ranked)
  | fuel + 1, remaining, scheduled, ranked =>
      match findReady? scheduled remaining with
      | none => throw <| cycleError remaining
      | some node =>
          let rankedNode := { node with rank := computeRank ranked node }
          let rest := remaining.filter (·.id != node.id)
          topoLoop fuel rest (node.id :: scheduled) (rankedNode :: ranked)

private def applyRanks (ranked : List Node) (nodes : Array Node) : Array Node :=
  nodes.map fun node => { node with rank := rankOf node.id ranked }

/-- Deterministic Kahn schedule followed by an independently decidable certificate. -/
def plan (specs : Array NodeSpec) : Except GraphError PlannedGraph := do
  let nodes ← buildNodes specs
  let (order, ranked) ← topoLoop nodes.size nodes.toList [] []
  let graph : Graph := ⟨applyRanks ranked nodes⟩
  let schedule : Schedule := ⟨order.toArray⟩
  if valid : schedule.Valid graph then
    pure { graph, schedule, valid }
  else
    throw { code := "LRX-PROOF-001", message := "generated schedule failed certification" }

theorem certified_schedule_respects_edges (planned : PlannedGraph) :
    ∀ node ∈ planned.graph.nodes.toList, ∀ dep ∈ node.deps.toList,
      planned.schedule.position dep < planned.schedule.position node.id := by
  intro node nodeMember dep depMember
  have nodeChecked := (List.all_eq_true.mp planned.valid.2.2.2) node nodeMember
  have depChecked := (List.all_eq_true.mp nodeChecked) dep depMember
  exact of_decide_eq_true depChecked

end Graph

end LeanRx
