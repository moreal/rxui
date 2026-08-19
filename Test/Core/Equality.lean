import LeanRx.Core.Equality

namespace LeanRxTest.Equality

def run : IO Unit := do
  unless LeanRx.RuntimeEq.same true true do
    throw <| IO.userError "Bool runtime equality rejected equal values"
  if LeanRx.RuntimeEq.same "lean" "rx" then
    throw <| IO.userError "String runtime equality accepted unequal values"
  let beyondSafeInteger : Int := 9007199254740993
  unless LeanRx.RuntimeEq.same beyondSafeInteger beyondSafeInteger do
    throw <| IO.userError "large Int runtime equality lost BigInt semantics"
  if LeanRx.RuntimeEq.same beyondSafeInteger (beyondSafeInteger + 1) then
    throw <| IO.userError "large Int runtime equality rounded distinct values"
  unless LeanRx.RuntimeEq.jsPlan Bool == .strict do
    throw <| IO.userError "Bool equality lowering is not strict equality"
  unless LeanRx.RuntimeEq.jsPlan Int == .bigint do
    throw <| IO.userError "Int equality lowering is not tied to BigInt"

example (a b : Int) : LeanRx.RuntimeEq.same a b = true ↔ a = b :=
  LeanRx.RuntimeEq.lawful a b

example (a b : String) : LeanRx.RuntimeEq.same a b = true ↔ a = b :=
  LeanRx.RuntimeEq.lawful a b

end LeanRxTest.Equality
