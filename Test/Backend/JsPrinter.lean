import LeanRx.Backend.JsPrinter

namespace LeanRxTest.Backend.JsPrinter

open LeanRx.Js

private def ident (value : String) : IO Ident :=
  match Ident.checked value with
  | .ok name => pure name
  | .error error => throw <| IO.userError error.message

private def print (mode : Printer.Mode) (module : Module) : IO String :=
  match Printer.module mode module with
  | .ok output => pure output
  | .error error => throw <| IO.userError s!"printer rejected fixture: {error.code}"

def run : IO Unit := do
  unless Printer.stringLiteral "quote\"\n\x00린" == "\"quote\\\"\\n\\u0000린\"" do
    throw <| IO.userError "JavaScript string escaping changed"
  unless Printer.literal (.bigint (-7)) == "(-7n)" &&
      Printer.literal (.bigint 9007199254740993) == "9007199254740993n" do
    throw <| IO.userError "JavaScript BigInt literal emission changed"
  unless Printer.literal .signedIntegerPattern == "/^-?[0-9]+$/" do
    throw <| IO.userError "closed signed-integer pattern emission changed"
  let evaluate ← ident "evaluate"
  let input ← ident "input"
  let one : Expr := .literal (.bigint 1)
  let module : Module :=
    { declarations := #[.function {
        name := evaluate
        params := #[input]
        body := #[.return (.binary .add (.ident input) one)]
      }]
      exports := #[{ localName := evaluate, exportName := evaluate }] }
  let readable ← print .readable module
  let compact ← print .compact module
  unless readable == "function evaluate(input) {\n  return (input + 1n);\n}\nexport { evaluate };\n" do
    throw <| IO.userError s!"readable JavaScript golden changed:\n{readable}"
  unless compact == "function evaluate(input){return (input+1n);}export{evaluate};" do
    throw <| IO.userError s!"compact JavaScript golden changed: {compact}"
  let repeated ← print .readable module
  unless repeated == readable do
    throw <| IO.userError "JavaScript printer bytes were not deterministic"
  let state ← ident "state"
  let extended : Module :=
    { declarations := #[.function {
        name := evaluate
        params := #[state]
        body := #[
          .assign (.index (.ident state) (.literal (.number 0))) (.literal (.bigint 2)),
          .ifThen (.literal (.boolean true)) <| .ofList [
            .return (.array <| .ofList [
              .index (.ident state) (.literal (.number 0)), .literal (.string "ok")
            ])
          ]
        ]
      }]
      exports := #[{ localName := evaluate, exportName := evaluate }] }
  let extendedSource ← print .compact extended
  unless extendedSource ==
      "function evaluate(state){state[0]=2n;if(true){return [state[0],\"ok\"];}}export{evaluate};" do
    throw <| IO.userError s!"extended JavaScript AST golden changed: {extendedSource}"
  let invalid : Module :=
    { declarations := #[]
      exports := #[{ localName := evaluate, exportName := evaluate }] }
  match Printer.module .readable invalid with
  | .ok _ => throw <| IO.userError "printer emitted an invalid JavaScript AST"
  | .error error =>
      unless error.code == "LRX-BE-011" do
        throw <| IO.userError "printer returned the wrong validation diagnostic"

end LeanRxTest.Backend.JsPrinter
