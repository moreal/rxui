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

private def mustPlan (spec : IntProgramSpec Chain) : IO CheckedIntProgram :=
  match LeanRx.Graph.planInt spec with
  | .ok checked => pure checked
  | .error error => throw <| IO.userError s!"typed Int planning failed: {error.code}"

def run : IO Unit := do
  let checked ← mustPlan doubledSpec
  unless checked.planned.graph.nodes.map (fun node => node.deps.map (·.value)) ==
      #[#[], #[0], #[1]] && checked.program.derived.map (·.evaluator.deps) == [[0]] do
    throw <| IO.userError "typed expression dependencies drifted from the proof program"
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

end LeanRxTest.Graph.IntProgram
