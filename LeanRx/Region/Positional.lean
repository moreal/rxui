import LeanRx.Region.Model

namespace LeanRx.Region

structure PositionalInstance where
  token : Nat
  node : LogicalNode
deriving Repr, BEq

structure PositionalResult where
  mounted : List PositionalInstance
  nextToken : Nat
  disposed : List Nat
  created : Nat
  scalarUpdates : Nat
deriving Repr, BEq

private def mountPositionalAux : List LogicalNode → Nat → PositionalResult
  | [], nextToken => {
      mounted := []
      nextToken
      disposed := []
      created := 0
      scalarUpdates := 0
    }
  | node :: nodes, nextToken =>
      let tail := mountPositionalAux nodes (nextToken + 1)
      { tail with
        mounted := { token := nextToken, node } :: tail.mounted
        created := tail.created + 1 }

def mountPositional (nodes : List LogicalNode) (nextToken : Nat := 0) : PositionalResult :=
  mountPositionalAux nodes nextToken

private def reconcilePositionalAux (current : List PositionalInstance) :
    List LogicalNode → Nat → PositionalResult
  | [], nextToken =>
      { mounted := []
        nextToken
        disposed := current.map (·.token)
        created := 0
        scalarUpdates := 0 }
  | node :: nodes, nextToken =>
      match current with
      | [] =>
          let tail := reconcilePositionalAux [] nodes (nextToken + 1)
          { tail with
            mounted := { token := nextToken, node } :: tail.mounted
            created := tail.created + 1 }
      | old :: rest =>
          let tail := reconcilePositionalAux rest nodes nextToken
          { tail with
            mounted := { old with node } :: tail.mounted
            scalarUpdates := tail.scalarUpdates + if old.node == node then 0 else 1 }

/-- Reconcile by position. Existing prefix tokens are retained, a removed suffix
is disposed, and an appended suffix receives fresh tokens. -/
def reconcilePositional (current : List PositionalInstance) (nodes : List LogicalNode)
    (nextToken : Nat) : PositionalResult :=
  reconcilePositionalAux current nodes nextToken

def positionalLogical (mounted : List PositionalInstance) : List LogicalNode :=
  mounted.map (·.node)

private theorem reconcilePositionalAux_logical (current : List PositionalInstance)
    (nodes : List LogicalNode) (nextToken : Nat) :
    positionalLogical (reconcilePositionalAux current nodes nextToken).mounted = nodes := by
  induction nodes generalizing current nextToken with
  | nil => simp [reconcilePositionalAux, positionalLogical]
  | cons node nodes ih =>
      cases current with
      | nil =>
          simp only [reconcilePositionalAux, positionalLogical, List.map_cons]
          exact congrArg (fun tail => node :: tail) (ih [] (nextToken + 1))
      | cons old rest =>
          simp only [reconcilePositionalAux, positionalLogical, List.map_cons]
          exact congrArg (fun tail => node :: tail) (ih rest nextToken)

theorem reconcilePositional_logical (current : List PositionalInstance)
    (nodes : List LogicalNode) (nextToken : Nat) :
    positionalLogical (reconcilePositional current nodes nextToken).mounted = nodes := by
  exact reconcilePositionalAux_logical current nodes nextToken

end LeanRx.Region
