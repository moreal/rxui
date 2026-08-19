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
  unless (LeanRx.JsType.array (.array .bigint)).debug == "array<array<bigint>>" do
    throw <| IO.userError "nested runtime type debug output is ambiguous"
  unless (LeanRx.JsType.object "x)\n\"").debug == "object(\"x)\\n\\\"\")" do
    throw <| IO.userError "runtime object names are not safely quoted"

end LeanRxTest.RuntimeRep
