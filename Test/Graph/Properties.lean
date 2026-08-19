import LeanRx.Proofs.PropagationSound

namespace LeanRxTest.Graph.Properties

open LeanRx.Abstract

structure Rng where
  state : Nat

abbrev GenM := StateM Rng

def draw (bound : Nat) : GenM Nat := do
  let rng ← get
  let next := (rng.state * 48271 + 1) % 2147483647
  set ({ state := next } : Rng)
  pure <| if bound = 0 then 0 else next % bound

inductive OpSpec where
  | add (dep : Nat) (delta : Int)
  | mod (dep : Nat) (divisor : Int)
  | add₂ (left right : Nat)
  | mul₂ (left right : Nat)
deriving Repr, BEq

namespace OpSpec

def evaluator : OpSpec → Eval
  | .add dep delta => .map dep (· + delta)
  | .mod dep divisor => .map dep (· % divisor)
  | .add₂ left right => .map₂ left right (· + ·)
  | .mul₂ left right => .map₂ left right (· * ·)

end OpSpec

structure CaseSpec where
  sourceCount : Nat
  initialSources : List Int
  operations : List OpSpec
  sinks : List Nat
  transactions : List (List (Nat × Int))
deriving Repr, BEq

private def generateOperations (sourceCount count : Nat) : GenM (List OpSpec) :=
  let rec loop : Nat → Nat → GenM (List OpSpec)
    | 0, _ => pure []
    | remaining + 1, index => do
      let available := sourceCount + index
      let kind ← draw 4
      let left ← draw available
      let right ← draw available
      let amount ← draw 11
      let operation := match kind with
        | 0 => .add left (Int.ofNat amount - 5)
        | 1 => .mod left (Int.ofNat (amount + 2))
        | 2 => .add₂ left right
        | _ => .mul₂ left right
      pure (operation :: (← loop remaining (index + 1)))
  loop count 0

private def generateTransactions (sourceCount count : Nat) : GenM (List (List (Nat × Int))) :=
  let rec loop : Nat → GenM (List (List (Nat × Int)))
    | 0 => pure []
    | remaining + 1 => do
      let writeCount ← draw 2
      let firstId ← draw sourceCount
      let firstValue ← draw 21
      let secondId ← draw sourceCount
      let secondValue ← draw 21
      let first := (firstId, Int.ofNat firstValue - 10)
      let writes := if writeCount = 0 then [first]
        else [first, (secondId, Int.ofNat secondValue - 10)]
      pure (writes :: (← loop remaining))
  loop count

def generateCase : GenM CaseSpec := do
  let sourceCount := 2
  let derivedExtra ← draw 5
  let derivedCount := derivedExtra + 1
  let firstSource ← draw 21
  let secondSource ← draw 21
  let operations ← generateOperations sourceCount derivedCount
  let secondSink ← draw (sourceCount + derivedCount)
  let transactions ← generateTransactions sourceCount 5
  pure {
    sourceCount
    initialSources := [Int.ofNat firstSource - 10, Int.ofNat secondSource - 10]
    operations
    sinks := [sourceCount + derivedCount - 1, secondSink]
    transactions
  }

private def buildDerived : Nat → List OpSpec → List DerivedStep
  | _, [] => []
  | id, operation :: rest =>
      { id, evaluator := operation.evaluator } :: buildDerived (id + 1) rest

private def buildSinks : Nat → List Nat → List SinkStep
  | _, [] => []
  | index, id :: rest =>
      { name := s!"sink{index}", evaluator := .map id (fun value => value) } ::
        buildSinks (index + 1) rest

def CaseSpec.program (spec : CaseSpec) : Program :=
  { sourceCount := spec.sourceCount
    derived := buildDerived spec.sourceCount spec.operations
    sinks := buildSinks 0 spec.sinks }

def CaseSpec.initialStore (spec : CaseSpec) : Store := fun id =>
  spec.initialSources[id]?.getD 0

def CaseSpec.initialState (spec : CaseSpec) : State :=
  let program := spec.program
  let store := Reference.runDerived program.derived spec.initialStore
  { store, sinkCache := Reference.observe program.sinks store }

def CaseSpec.sourceTransactions (spec : CaseSpec) : List SourceTransaction :=
  spec.transactions.map fun writes => writes.map fun (id, value) => { id, value }

private def storesAgreeThrough (size : Nat) (left right : Store) : Bool :=
  (List.range size).all fun id => decide (left id = right id)

private def insertId (id : Nat) (changed : List Nat) : List Nat :=
  id :: changed.filter (· != id)

private def traceReachable (program : Program) : List TraceEvent → List Nat → Bool
  | [], _ => true
  | .sourceChanged id :: rest, changed =>
      decide (id < program.sourceCount) && traceReachable program rest (insertId id changed)
  | .derivedPending id :: rest, changed =>
      match program.derived.find? (·.id == id) with
      | some step => Optimized.isPending step.evaluator.deps changed &&
          traceReachable program rest changed
      | none => false
  | .derivedChanged id :: rest, changed =>
      traceReachable program rest (insertId id changed)
  | .sinkPending name :: rest, changed =>
      match program.sinks.find? (·.name == name) with
      | some sink => Optimized.isPending sink.evaluator.deps changed &&
          traceReachable program rest changed
      | none => false
  | _ :: rest, changed => traceReachable program rest changed

private def isSubsequence [BEq α] : List α → List α → Bool
  | [], _ => true
  | _ :: _, [] => false
  | expected@(_ :: _), actual :: rest =>
      if expected.head? == some actual then isSubsequence expected.tail rest
      else isSubsequence expected rest

private def replayLabel (seed caseIndex : Nat) (spec : CaseSpec) : String :=
  s!"seed={seed} case={caseIndex} spec={repr spec}"

private def runTransactions (seed caseIndex : Nat) (spec : CaseSpec)
    (program : Program) : List SourceTransaction → State → IO Unit
  | [], _ => pure ()
  | transaction :: rest, old => do
      let reference := Reference.run program old transaction
      let optimized := Optimized.run program old transaction
      let nodeCount := spec.sourceCount + spec.operations.length
      unless storesAgreeThrough nodeCount reference.store optimized.store do
        throw <| IO.userError s!"store mismatch: {replayLabel seed caseIndex spec}"
      unless reference.observations == optimized.observations do
        throw <| IO.userError s!"observation mismatch: {replayLabel seed caseIndex spec}"
      unless optimized.derivedEvaluations ≤ reference.derivedEvaluations do
        throw <| IO.userError s!"derived work increased: {replayLabel seed caseIndex spec}"
      unless optimized.sinkEvaluations ≤ reference.sinkEvaluations do
        throw <| IO.userError s!"sink work increased: {replayLabel seed caseIndex spec}"
      unless traceReachable program optimized.trace [] do
        throw <| IO.userError s!"trace left affected closure: {replayLabel seed caseIndex spec}"
      let derivedOrder := program.derived.map (·.id)
      let evaluatedDerived := optimized.trace.filterMap fun event => match event with
        | .derivedEvaluated id => some id
        | _ => none
      unless isSubsequence evaluatedDerived derivedOrder do
        throw <| IO.userError s!"derived trace violated schedule: {replayLabel seed caseIndex spec}"
      let sinkOrder := program.sinks.map (·.name)
      let evaluatedSinks := optimized.trace.filterMap fun event => match event with
        | .sinkEvaluated name => some name
        | _ => none
      unless isSubsequence evaluatedSinks sinkOrder do
        throw <| IO.userError s!"sink trace violated order: {replayLabel seed caseIndex spec}"
      let next := optimized.nextState
      runTransactions seed caseIndex spec program rest next

def runWithSeed (seed : Nat) (caseCount : Nat := 40) : IO Unit :=
  let rec loop : Nat → Nat → Rng → IO Unit
    | 0, _, _ => pure ()
    | remaining + 1, caseIndex, rng => do
      let (spec, nextRng) := generateCase.run rng
      runTransactions seed caseIndex spec spec.program spec.sourceTransactions spec.initialState
      loop remaining (caseIndex + 1) nextRng
  loop caseCount 0 { state := seed }

def run : IO Unit :=
  runWithSeed 195936478

end LeanRxTest.Graph.Properties
