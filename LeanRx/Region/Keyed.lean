import LeanRx.Region.Model

namespace LeanRx.Region

structure KeyedItem where
  key : Nat
  node : LogicalNode
deriving Repr, BEq

structure KeyedList where
  private mk ::
  items : List KeyedItem
deriving Repr, BEq

namespace KeyedList

private def unique : List KeyedItem → Bool
  | [] => true
  | item :: rest => ¬rest.any (fun other => other.key == item.key) && unique rest

def create (items : List KeyedItem) : Except Error KeyedList :=
  if unique items then .ok ⟨items⟩
  else .error {
    code := "LRX-REGION-001"
    message := "keyed region items must have unique keys"
  }

def toList (value : KeyedList) : List KeyedItem := value.items

def keys (value : KeyedList) : List Nat := value.items.map (·.key)

end KeyedList

structure KeyedInstance where
  token : Nat
  key : Nat
  node : LogicalNode
deriving Repr, BEq

structure KeyedResult where
  mounted : List KeyedInstance
  nextToken : Nat
  disposed : List Nat
  created : Nat
  moved : Nat
  scalarUpdates : Nat
deriving Repr, BEq

private def findKey (key : Nat) : List KeyedInstance → Option KeyedInstance
  | [] => none
  | entry :: rest => if entry.key == key then some entry else findKey key rest

private def findKeyIndex (key : Nat) : List KeyedInstance → Nat → Option Nat
  | [], _ => none
  | entry :: rest, index =>
      if entry.key == key then some index else findKeyIndex key rest (index + 1)

private def targetContains (target : List KeyedItem) (key : Nat) : Bool :=
  target.any (fun item => item.key == key)

private def reconcileKeyedAux (current : List KeyedInstance) :
    List KeyedItem → Nat → Nat → KeyedResult
  | [], nextToken, _ => {
      mounted := []
      nextToken
      disposed := []
      created := 0
      moved := 0
      scalarUpdates := 0
    }
  | item :: items, nextToken, targetIndex =>
      match findKey item.key current with
      | none =>
          let tail := reconcileKeyedAux current items (nextToken + 1) (targetIndex + 1)
          { tail with
            mounted := { token := nextToken, key := item.key, node := item.node } :: tail.mounted
            created := tail.created + 1 }
      | some old =>
          let tail := reconcileKeyedAux current items nextToken (targetIndex + 1)
          let moved := match findKeyIndex item.key current 0 with
            | some oldIndex => if oldIndex == targetIndex then 0 else 1
            | none => 0
          { tail with
            mounted := { token := old.token, key := item.key, node := item.node } :: tail.mounted
            moved := tail.moved + moved
            scalarUpdates := tail.scalarUpdates + if old.node == item.node then 0 else 1 }

def mountKeyed (target : KeyedList) (nextToken : Nat := 0) : KeyedResult :=
  reconcileKeyedAux [] target.items nextToken 0

/-- Reconcile by key. Retained keys keep tokens across reorders; only absent keys
are disposed and only new keys receive fresh tokens. -/
def reconcileKeyed (current : List KeyedInstance) (target : KeyedList)
    (nextToken : Nat) : KeyedResult :=
  let result := reconcileKeyedAux current target.items nextToken 0
  { result with
    disposed := (current.filter fun entry => ¬targetContains target.items entry.key).map
      (·.token) }

def keyedLogical (mounted : List KeyedInstance) : List KeyedItem :=
  mounted.map fun entry => { key := entry.key, node := entry.node }

private theorem reconcileKeyedAux_logical (current : List KeyedInstance)
    (items : List KeyedItem) (nextToken targetIndex : Nat) :
    keyedLogical (reconcileKeyedAux current items nextToken targetIndex).mounted = items := by
  induction items generalizing nextToken targetIndex with
  | nil => simp [reconcileKeyedAux, keyedLogical]
  | cons item items ih =>
      simp only [reconcileKeyedAux]
      split <;> simp only [keyedLogical, List.map_cons]
      · exact congrArg (fun tail => item :: tail) (ih (nextToken + 1) (targetIndex + 1))
      · exact congrArg (fun tail => item :: tail) (ih nextToken (targetIndex + 1))

theorem reconcileKeyed_logical (current : List KeyedInstance) (target : KeyedList)
    (nextToken : Nat) :
    keyedLogical (reconcileKeyed current target nextToken).mounted = target.toList := by
  exact reconcileKeyedAux_logical current target.items nextToken 0

end LeanRx.Region
