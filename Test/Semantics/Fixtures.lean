import LeanRx.Semantics.Reference

namespace LeanRxTest.Semantics.Fixtures

open LeanRx.Abstract

def diamondProgram : Program :=
  { sourceCount := 1
    derived :=
      [ { id := 1, evaluator := .map 0 (· + 10) }
      , { id := 2, evaluator := .map 0 (· * 2) }
      , { id := 3, evaluator := .map₂ 1 2 (· + ·) }
      ]
    sinks := [{ name := "total", evaluator := .map 3 id }] }

def oldStore : Store := fun id =>
  match id with
  | 0 => 1
  | 1 => 11
  | 2 => 2
  | 3 => 13
  | _ => 0

def oldState : State := { store := oldStore, sinkCache := [13] }

theorem diamondDerivedValid : DerivedCacheValid oldStore diamondProgram.derived := by
  constructor
  · rfl
  constructor
  · rfl
  constructor
  · rfl
  · constructor

theorem diamondSinkValid : SinkCacheValid oldStore diamondProgram.sinks oldState.sinkCache := by
  constructor
  · rfl
  · constructor

theorem diamondWellFormed : diamondProgram.WellFormed := by
  constructor
  · intro step member
    simp [diamondProgram] at member
    rcases member with rfl | rfl | rfl <;> decide
  · intro step member dep depMember
    simp [diamondProgram] at member
    rcases member with rfl | rfl | rfl
    · have same : dep = 0 := by simpa [Eval.map] using depMember
      subst dep
      decide
    · have same : dep = 0 := by simpa [Eval.map] using depMember
      subst dep
      decide
    · have alternatives : dep = 1 ∨ dep = 2 := by
        simpa [Eval.map₂] using depMember
      rcases alternatives with rfl | rfl <;> decide
  · decide

def countToThree : SourceTransaction := [{ id := 0, value := 3 }]

theorem countToThreeValid : countToThree.Valid diamondProgram := by
  intro write member
  simp [countToThree] at member
  subst write
  decide

end LeanRxTest.Semantics.Fixtures
