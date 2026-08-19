import LeanRx.Proofs.PropagationSound
import Test.Semantics.Fixtures

namespace LeanRxTest.PropagationSound

open LeanRx.Abstract
open LeanRxTest.Semantics.Fixtures

theorem diamond_observations_agree :
    (Optimized.run diamondProgram oldState countToThree).observations =
      (Reference.run diamondProgram oldState countToThree).observations := by
  exact optimized_equivalent_to_reference diamondProgram diamondWellFormed oldState
    diamondDerivedValid diamondSinkValid countToThree countToThreeValid

theorem diamond_stores_agree :
    (Optimized.run diamondProgram oldState countToThree).store =
      (Reference.run diamondProgram oldState countToThree).store := by
  exact optimized_store_eq_reference diamondProgram oldState diamondDerivedValid countToThree
    countToThreeValid

def initialized : ValidState diamondProgram :=
  Reference.initializeValid diamondProgram diamondWellFormed fun id =>
    if id = 0 then 1 else 0

def afterCount : ValidState diamondProgram :=
  optimizedNextValid diamondProgram diamondWellFormed initialized countToThree countToThreeValid

theorem repeated_optimized_state_is_valid : afterCount.state.Valid diamondProgram :=
  afterCount.valid

def nestedCountToThree : NestedTransaction :=
  [[{ id := 0, value := 2 }], [{ id := 0, value := 3 }]]

theorem nestedCountToThreeValid : nestedCountToThree.Valid diamondProgram := by
  intro transaction transactionMember write writeMember
  simp [nestedCountToThree] at transactionMember
  rcases transactionMember with rfl | rfl <;> simp at writeMember <;> subst write <;> decide

theorem nested_diamond_observations_agree :
    (Optimized.run diamondProgram oldState nestedCountToThree.flatten).observations =
      (Reference.run diamondProgram oldState nestedCountToThree.flatten).observations := by
  exact optimized_equivalent_for_flattened_nested_writes diamondProgram diamondWellFormed oldState
    diamondDerivedValid diamondSinkValid nestedCountToThree nestedCountToThreeValid

def run : IO Unit := do
  let optimized := Optimized.run diamondProgram oldState countToThree
  let reference := Reference.run diamondProgram oldState countToThree
  unless optimized.observations == reference.observations do
    throw <| IO.userError "proved propagation fixture disagreed at runtime"
  let nested := Optimized.run diamondProgram oldState nestedCountToThree.flatten
  unless nested.store 3 == 19 && nested.observations == [19] do
    throw <| IO.userError "nested transaction flattening changed propagation"

end LeanRxTest.PropagationSound
