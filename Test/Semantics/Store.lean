import LeanRx.Semantics.Store

namespace LeanRxTest.Semantics.Store

def base : LeanRx.Abstract.Store := fun id => if id = 0 then 1 else 0

def doubled : LeanRx.Abstract.Eval := .map 0 (· * 2)
def total : LeanRx.Abstract.Eval := .map₂ 0 1 (· + ·)

def run : IO Unit := do
  let transaction : LeanRx.Abstract.SourceTransaction :=
    [{ id := 0, value := 2 }, { id := 0, value := 3 }, { id := 1, value := 4 }]
  let committed := transaction.apply base
  unless committed 0 == 3 && committed 1 == 4 do
    throw <| IO.userError "source transaction did not retain final batched values"
  unless doubled.run committed == 6 do
    throw <| IO.userError "abstract unary evaluator is incorrect"
  unless total.run committed == 7 do
    throw <| IO.userError "abstract binary evaluator is incorrect"

example (left right : LeanRx.Abstract.Store) (h : left 0 = right 0) :
    doubled.run left = doubled.run right := by
  apply doubled.congr
  intro id member
  change id ∈ [0] at member
  simp at member
  subst id
  exact h

end LeanRxTest.Semantics.Store
