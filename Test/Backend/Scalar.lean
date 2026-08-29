import LeanRx.Backend.Scalar
import LeanRx.Backend.Manifest
import LeanRx.Backend.JsPrinter
import LeanRx.Lower.RxExpr
import Test.Core.Expr

namespace LeanRxTest.Backend.Scalar

open LeanRxTest.Expr

private def input (name : String) (valueType : LeanRx.RuntimeTypeId) :
    LeanRx.Backend.Scalar.InputSpec :=
  { name, valueType }

private def emit (name : String) (inputs : Array LeanRx.Backend.Scalar.InputSpec)
    (value : LeanRx.ReactiveIR.Expr α) :
    IO LeanRx.Backend.Scalar.Emitted :=
  match LeanRx.Backend.Scalar.moduleFor name inputs value with
  | .ok emitted => pure emitted
  | .error error => throw <| IO.userError s!"scalar module emission failed: {error.code}"

def run : IO Unit := do
  let subtotalModule ← emit "subtotal" #[input "price" .int, input "quantity" .int,
      input "threshold" .int] <|
    LeanRx.Lower.rxExpr subtotal
  let subtotalSource ← match LeanRx.Js.Printer.module .readable subtotalModule.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError error.message
  unless subtotalSource ==
      "function subtotal(price, quantity, threshold) {\n  return price * quantity;\n}\nexport { subtotal };\n" do
    throw <| IO.userError s!"scalar module golden changed:\n{subtotalSource}"
  let manifest := (LeanRx.Backend.ArtifactManifest.scalar
    "subtotal.mjs" subtotalModule).json
  unless manifest ==
      "{\"compilerVersion\":\"0.1.0-dev\",\"leanToolchain\":\"leanprover/lean4:v4.33.0\",\"module\":\"subtotal.mjs\",\"runtimeAbi\":18,\"exports\":[\"subtotal\"],\"inputs\":[{\"name\":\"price\",\"generatedName\":\"price\",\"type\":\"int\"},{\"name\":\"quantity\",\"generatedName\":\"quantity\",\"type\":\"int\"},{\"name\":\"threshold\",\"generatedName\":\"threshold\",\"type\":\"int\"}],\"resultType\":\"int\",\"features\":[\"scalar\"]}\n" do
    throw <| IO.userError s!"scalar artifact manifest changed:\n{manifest}"
  let intMod : LeanRx.ReactiveIR.Expr Int := .binary .intMod
    (.input .int 0 "left") (.input .int 1 "right")
  let modModule ← emit "mod" #[input "left" .int, input "right" .int] intMod
  unless modModule.module.declarations.size == 2 do
    throw <| IO.userError "Int.mod did not emit exactly one semantic helper"
  let repeatedMod : LeanRx.ReactiveIR.Expr Int := .binary .intAdd intMod intMod
  let repeatedModule ← emit "repeatedMod" #[input "left" .int, input "right" .int] repeatedMod
  unless repeatedModule.module.declarations.size == 2 do
    throw <| IO.userError "repeated Int.mod emitted duplicate semantic helpers"
  let display : LeanRx.ReactiveIR.Expr String :=
    .unary .intToString (.input .int 0 "String")
  let shadowed ← emit "String" #[input "String" .int] display
  let shadowedSource ← match LeanRx.Js.Printer.module .compact shadowed.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError error.message
  unless shadowedSource.contains "function String_2(String_3)" &&
      shadowedSource.contains "String(String_3)" do
    throw <| IO.userError "user identifiers shadowed the backend-owned String builtin"
  let badInput : LeanRx.ReactiveIR.Expr Int := .input .int 2 "missing"
  match LeanRx.Backend.Scalar.moduleFor "bad" #[input "only" .int] badInput with
  | .ok _ => throw <| IO.userError "out-of-range Reactive IR input emitted JavaScript"
  | .error error =>
      unless error.code == "LRX-BE-013" do
        throw <| IO.userError "out-of-range input returned the wrong diagnostic"
  let conflicting : LeanRx.ReactiveIR.Expr Int := .conditional
    (.input .bool 0 "value") (.input .int 0 "value") (.literal (.int 0))
  match LeanRx.Backend.Scalar.moduleFor "conflicting" #[input "value" .int] conflicting with
  | .ok _ => throw <| IO.userError "conflicting Reactive IR input types emitted JavaScript"
  | .error error =>
      unless error.code == "LRX-BE-019" do
        throw <| IO.userError "conflicting input type returned the wrong diagnostic"
  let selected : LeanRx.ReactiveIR.Expr String := .vectorGet .string
    (.input (.vector .string 3) 0 "panels") (.input (.fin 3) 1 "selected")
  let selectedModule ← emit "selected"
    #[input "panels" (.vector .string 3), input "selected" (.fin 3)] selected
  let selectedSource ← match LeanRx.Js.Printer.module .readable selectedModule.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError error.message
  unless selectedSource ==
      "function selected(panels, selected_2) {\n  return panels[selected_2];\n}\nexport { selected };\n" do
    throw <| IO.userError s!"proof-safe vector access golden changed:\n{selectedSource}"

end LeanRxTest.Backend.Scalar
