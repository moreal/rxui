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
  unless diamond.trace == [
      .sourceChanged 0,
      .derivedPending 1, .derivedEvaluated 1, .derivedChanged 1,
      .derivedPending 2, .derivedEvaluated 2, .derivedChanged 2,
      .derivedPending 3, .derivedEvaluated 3, .derivedChanged 3,
      .sinkPending "total", .sinkEvaluated "total"
    ] do
    throw <| IO.userError s!"diamond affected trace changed: {repr diamond.trace}"
  let parity := LeanRx.Abstract.Optimized.run parityProgram parityOld
    [{ id := 0, value := 3 }]
  unless parity.store 1 == 1 && parity.store 2 == 101 do
    throw <| IO.userError "same-value propagation changed downstream caches"
  unless parity.observations == [1, 101] do
    throw <| IO.userError "same-value propagation changed observations"
  unless parity.derivedEvaluations == 1 && parity.sinkEvaluations == 0 do
    throw <| IO.userError
      s!"same-value stop failed: derived={parity.derivedEvaluations}, sinks={parity.sinkEvaluations}"
  unless parity.trace == [
      .sourceChanged 0, .derivedPending 1, .derivedEvaluated 1
    ] do
    throw <| IO.userError s!"same-value stop awakened a consumer: {repr parity.trace}"
  let sourceOnly : Program := { sourceCount := 1, derived := [], sinks := [] }
  let sourceOld : State := { store := fun _ => 1, sinkCache := [] }
  let sourceResult := LeanRx.Abstract.Optimized.run sourceOnly sourceOld
    [{ id := 0, value := 3 }]
  unless sourceResult.store 0 == 3 && sourceResult.observations.isEmpty &&
      sourceResult.derivedEvaluations == 0 && sourceResult.sinkEvaluations == 0 &&
      sourceResult.trace == [.sourceChanged 0] do
    throw <| IO.userError "source write without consumers propagated work"
  let canceled := LeanRx.Abstract.Optimized.run sourceOnly sourceOld
    [{ id := 0, value := 3 }, { id := 0, value := 1 }]
  unless canceled.trace.isEmpty && canceled.store 0 == 1 do
    throw <| IO.userError "batched writes did not use the final source value"

end LeanRxTest.Semantics.Optimized
