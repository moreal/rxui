import LeanRx.Semantics.Optimized
import Test.Semantics.Fixtures

namespace LeanRxTest.Semantics.Optimized

open LeanRx.Abstract

def parityProgram : Program :=
  { sourceCount := 1
    derived :=
      [ { id := 1, evaluator := .map 0 (fun value => value % 2) }
      , { id := 2, evaluator := .map 1 (· + 100) }
      ]
    sinks :=
      [ { name := "parity", evaluator := .map 1 id }
      , { name := "downstream", evaluator := .map 2 id }
      ] }

def parityOldStore : Store := fun id =>
  match id with
  | 0 => 1
  | 1 => 1
  | 2 => 101
  | _ => 0

def parityOld : State := { store := parityOldStore, sinkCache := [1, 101] }

def run : IO Unit := do
  let diamond := LeanRx.Abstract.Optimized.run
    LeanRxTest.Semantics.Fixtures.diamondProgram
    LeanRxTest.Semantics.Fixtures.oldState
    LeanRxTest.Semantics.Fixtures.countToThree
  unless diamond.store 3 == 19 && diamond.observations == [19] do
    throw <| IO.userError "optimized diamond result is incorrect"
  unless diamond.derivedEvaluations == 3 && diamond.sinkEvaluations == 1 do
    throw <| IO.userError "optimized diamond did not evaluate each affected node once"
  let parity := LeanRx.Abstract.Optimized.run parityProgram parityOld
    [{ id := 0, value := 3 }]
  unless parity.store 1 == 1 && parity.store 2 == 101 do
    throw <| IO.userError "same-value propagation changed downstream caches"
  unless parity.observations == [1, 101] do
    throw <| IO.userError "same-value propagation changed observations"
  unless parity.derivedEvaluations == 1 && parity.sinkEvaluations == 0 do
    throw <| IO.userError
      s!"same-value stop failed: derived={parity.derivedEvaluations}, sinks={parity.sinkEvaluations}"

end LeanRxTest.Semantics.Optimized
