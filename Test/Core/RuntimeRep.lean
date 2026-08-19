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
  unless LeanRx.RuntimeRep.debug (Vector String 3) == "array<string>" &&
      LeanRx.RuntimeRep.typeId (Vector String 3) == .vector .string 3 &&
      LeanRx.RuntimeRep.erasesProofs (Vector String 3) do
    throw <| IO.userError "Vector runtime representation must erase its static length"
  unless LeanRx.RuntimeRep.debug (Fin 3) == "number" &&
      LeanRx.RuntimeRep.typeId (Fin 3) == .fin 3 &&
      LeanRx.RuntimeRep.erasesProofs (Fin 3) do
    throw <| IO.userError "Fin runtime representation must erase its bound proof"
  unless LeanRx.RuntimeRep.typeId (Vector (Vector Int 2) 4) ==
      .vector (.vector .int 2) 4 do
    throw <| IO.userError "nested Vector runtime identity lost an indexed length"
  unless (LeanRx.RuntimeTypeId.vector (.fin 4) 2).debug == "vector<fin<4>,2>" do
    throw <| IO.userError "dependent runtime type diagnostics are ambiguous"
  unless (LeanRx.RuntimeTypeId.list (.record "TodoItem")).debug ==
      "list<record<TodoItem>>" do
    throw <| IO.userError "dynamic record/list runtime metadata changed"
  unless (LeanRx.JsType.array (.array .bigint)).debug == "array<array<bigint>>" do
    throw <| IO.userError "nested runtime type debug output is ambiguous"
  unless (LeanRx.JsType.object "x)\n\"").debug == "object(\"x)\\n\\\"\")" do
    throw <| IO.userError "runtime object names are not safely quoted"

end LeanRxTest.RuntimeRep
