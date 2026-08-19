import LeanRx.Core.RuntimeRep

namespace LeanRxTest.RuntimeRep

def run : IO Unit := do
  unless LeanRx.RuntimeRep.debug Bool == "boolean" do
    throw <| IO.userError "Bool runtime representation changed"
  unless LeanRx.RuntimeRep.debug String == "string" do
    throw <| IO.userError "String runtime representation changed"
  unless LeanRx.RuntimeRep.debug Int == "bigint" do
    throw <| IO.userError "Lean Int must not lower to JavaScript Number"
  unless LeanRx.RuntimeRep.debug Nat == "bigint" do
    throw <| IO.userError "Lean Nat must not lower to JavaScript Number"

end LeanRxTest.RuntimeRep
