namespace LeanRx.Region

/-- Stable dynamic-region diagnostic. Region construction and lowering fail
before emitting browser code. -/
structure Error where
  code : String
  message : String
  path : Array String := #[]
deriving Repr, BEq

/-- Reference-only logical DOM used by differential tests. Runtime rendering is
direct DOM plus local regions; this value is never shipped as a virtual DOM. -/
inductive LogicalNode where
  | text (value : String)
  | element (tag : String) (attributes : List (String × String))
      (children : List LogicalNode)
deriving Repr, BEq

/-- Mounted conditional branch with an opaque identity token. -/
structure ConditionalInstance where
  token : Nat
  branch : Bool
  node : LogicalNode
deriving Repr, BEq

structure ConditionalResult where
  mounted : ConditionalInstance
  nextToken : Nat
  disposed : List Nat
  replacements : Nat
  scalarUpdates : Nat
deriving Repr, BEq

/-- Full reference result for a conditional region. -/
def conditionalReference (branch : Bool) (whenTrue whenFalse : LogicalNode) : LogicalNode :=
  if branch then whenTrue else whenFalse

def mountConditional (branch : Bool) (whenTrue whenFalse : LogicalNode)
    (token : Nat := 0) : ConditionalResult :=
  { mounted := { token, branch, node := conditionalReference branch whenTrue whenFalse }
    nextToken := token + 1
    disposed := []
    replacements := 0
    scalarUpdates := 0 }

/-- Reuse the branch identity for stable-shape scalar updates; replace and
dispose exactly once when the branch changes. -/
def reconcileConditional (current : ConditionalInstance) (nextBranch : Bool)
    (whenTrue whenFalse : LogicalNode) (nextToken : Nat) : ConditionalResult :=
  let nextNode := conditionalReference nextBranch whenTrue whenFalse
  if current.branch == nextBranch then
    { mounted := { current with node := nextNode }
      nextToken
      disposed := []
      replacements := 0
      scalarUpdates := if current.node == nextNode then 0 else 1 }
  else
    { mounted := { token := nextToken, branch := nextBranch, node := nextNode }
      nextToken := nextToken + 1
      disposed := [current.token]
      replacements := 1
      scalarUpdates := 0 }

theorem reconcileConditional_logical (current : ConditionalInstance) (nextBranch : Bool)
    (whenTrue whenFalse : LogicalNode) (nextToken : Nat) :
    (reconcileConditional current nextBranch whenTrue whenFalse nextToken).mounted.node =
      conditionalReference nextBranch whenTrue whenFalse := by
  unfold reconcileConditional
  split <;> rfl

end LeanRx.Region
