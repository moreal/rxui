import LeanRx.Graph.IntProgram

namespace LeanRxTest.Graph.IntProgram

open LeanRx
open LeanRx.Abstract

abbrev Chain : Schema :=
  .field "source" Int <| .field "derived" Int .empty

def source : Field Chain Int := .here
def derived : Field Chain Int := .there .here
def allInt : AllInt Chain := .field (.field .empty)

def doubled := RxExpr.binary .intMul
  (RxExpr.read source) (RxExpr.literal (.int 2))

def plusOne := RxExpr.binary .intAdd
  (RxExpr.read source) (RxExpr.literal (.int 1))

def specFor (expr : RxExpr Chain deps Int) : IntProgramSpec Chain :=
  { allInt
    sourceCount := 1
    values := [.source source, .derived derived expr]
    sinks := [.observe "result" (RxExpr.read derived)] }

def doubledSpec := specFor doubled

def plusOneSpec := specFor plusOne

def misalignedSpec : IntProgramSpec Chain :=
  { allInt
    sourceCount := 1
    values := [.source derived, .derived source doubled]
    sinks := [.observe "result" (RxExpr.read derived)] }

def phantomSourceSpec : IntProgramSpec Chain :=
  { allInt
    sourceCount := 3
    values := [.source source, .source derived]
    sinks := [] }

def lateSourceSpec : IntProgramSpec Chain :=
  { allInt
    sourceCount := 1
    values := [.derived source (RxExpr.literal (.int 0)), .source derived]
    sinks := [] }

abbrev Cycle : Schema :=
  .field "a" Int <| .field "b" Int .empty

def cycleA : Field Cycle Int := .here
def cycleB : Field Cycle Int := .there .here
def cycleAllInt : AllInt Cycle := .field (.field .empty)

def cycleSpan (line offset : Nat) : SourceSpan :=
  { file := "app/TypedCycle.lean"
    start := { line, column := 1, byteOffset := offset }
    stop := { line, column := 2, byteOffset := offset + 1 } }

def cycleSpec : IntProgramSpec Cycle :=
  { allInt := cycleAllInt
    sourceCount := 0
    values :=
      [ .derived cycleA (RxExpr.read cycleB) (cycleSpan 2 10)
      , .derived cycleB (RxExpr.read cycleA) (cycleSpan 3 20)
      ]
    sinks := [] }

abbrev Forward : Schema :=
  .field "source" Int <| .field "first" Int <| .field "later" Int .empty

def forwardSource : Field Forward Int := .here
def forwardFirst : Field Forward Int := .there .here
def forwardLater : Field Forward Int := .there (.there .here)
def forwardAllInt : AllInt Forward := .field (.field (.field .empty))

def forwardSpec : IntProgramSpec Forward :=
  { allInt := forwardAllInt
    sourceCount := 1
    values :=
      [ .source forwardSource
      , .derived forwardFirst (RxExpr.read forwardLater)
      , .derived forwardLater (RxExpr.read forwardSource)
      ]
    sinks := [] }

private def mustPlan (spec : IntProgramSpec Chain) : IO CheckedIntProgram :=
  match LeanRx.Graph.planInt spec with
  | .ok checked => pure checked
  | .error error => throw <| IO.userError s!"typed Int planning failed: {error.code}"

def run : IO Unit := do
  let checked ← mustPlan doubledSpec
  unless checked.planned.graph.nodes.map (fun node => node.deps.map (·.value)) ==
      #[#[], #[0], #[1]] && checked.program.derived.map (·.evaluator.deps) == [[0]] do
    throw <| IO.userError "typed expression dependencies drifted from the proof program"
  unless checked.planned.graph.nodes.map (·.valueType) == #[.int, .int, .int] do
    throw <| IO.userError "typed Int sink drifted to a different graph runtime type"
  unless checked.planned.graph.nodes.map (·.evaluator) == #["", doubled.debug, (RxExpr.read derived).debug] do
    throw <| IO.userError "graph evaluator identity did not derive from the staged expression"
  let initial : Abstract.Store := fun id => if id = 0 then 3 else 0
  let initialized := Reference.initState checked.program initial
  unless initialized.store 1 == 6 && initialized.sinkCache == [6] do
    throw <| IO.userError "derived abstract evaluator disagreed with staged expression"
  let changed ← mustPlan plusOneSpec
  let changedState := Reference.initState changed.program initial
  unless changed.planned.graph.nodes.map (·.evaluator) ==
      #["", plusOne.debug, (RxExpr.read derived).debug] &&
      changedState.store 1 == 4 && changedState.sinkCache == [4] do
    throw <| IO.userError "changing one staged expression did not change both connected models"
  match LeanRx.Graph.planInt misalignedSpec with
  | .ok _ => throw <| IO.userError "misaligned typed fields unexpectedly planned"
  | .error error =>
      unless error.code == "LRX-TYPE-007" do
        throw <| IO.userError s!"wrong typed alignment diagnostic: {error.code}"
  for spec in [phantomSourceSpec, lateSourceSpec] do
    match LeanRx.Graph.planInt spec with
    | .ok _ => throw <| IO.userError "invalid typed source prefix unexpectedly planned"
    | .error error =>
        unless error.code == "LRX-TYPE-008" do
          throw <| IO.userError s!"wrong typed source-prefix diagnostic: {error.code}"
  match LeanRx.Graph.planInt cycleSpec with
  | .ok _ => throw <| IO.userError "typed expression cycle unexpectedly planned"
  | .error error =>
      unless error.code == "LRX-GRAPH-001" && error.path == #["a", "b", "a"] &&
          error.spans == #[cycleSpan 2 10, cycleSpan 3 20, cycleSpan 2 10] do
        throw <| IO.userError s!"typed cycle lost graph diagnostics: {error.code}"
  match LeanRx.Graph.planInt forwardSpec with
  | .ok _ => throw <| IO.userError "forward proof-subset dependency unexpectedly planned"
  | .error error =>
      unless error.code == "LRX-PROOF-002" && error.message.contains "dependency order" do
        throw <| IO.userError "forward dependency lost its proof-subset restriction diagnostic"

end LeanRxTest.Graph.IntProgram
