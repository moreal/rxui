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
  unless Printer.literal (.bigint (-7)) == "-7n" &&
      Printer.literal (.bigint 9007199254740993) == "9007199254740993n" do
    throw <| IO.userError "JavaScript BigInt literal emission changed"
  unless Printer.literal .signedIntegerPattern == "/^-?[0-9]+$/" do
    throw <| IO.userError "closed signed-integer pattern emission changed"
  unless Printer.literal .naturalPattern == "/^[0-9]+$/" &&
      Printer.literal .asciiTrimPattern == "/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g" do
    throw <| IO.userError "closed form validation pattern emission changed"
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
  unless readable == "function evaluate(input) {\n  return input + 1n;\n}\nexport { evaluate };\n" do
    throw <| IO.userError s!"readable JavaScript golden changed:\n{readable}"
  unless compact == "function evaluate(input){return input+1n;}export{evaluate};" do
    throw <| IO.userError s!"compact JavaScript golden changed: {compact}"
  let repeated ← print .readable module
  unless repeated == readable do
    throw <| IO.userError "JavaScript printer bytes were not deterministic"
  let state ← ident "state"
  let item ← ident "item"
  let extended : Module :=
    { declarations := #[.function {
        name := evaluate
        params := #[state]
        body := #[
          .assign (.index (.ident state) (.literal (.number 0))) (.literal (.bigint 2)),
          .forOf item (.ident state) <| .ofList [.expr (.ident item)],
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
      "function evaluate(state){state[0]=2n;for(const item of state){item;}if(true){return [state[0],\"ok\"];}}export{evaluate};" do
    throw <| IO.userError s!"extended JavaScript AST golden changed: {extendedSource}"
  -- `!(a === b)` prints as `a !== b` and binds like an equality, so it is
  -- grouped where an equality would be and not otherwise.
  let negated : Module :=
    { declarations := #[.function {
        name := evaluate
        params := #[state, item]
        body := #[
          .ifThen (.unary .not (.binary .eq (.ident state) (.ident item))) <| .ofList [
            .return (.binary .add (.ident state)
              (.unary .not (.binary .eq (.ident item) (.literal (.number 1)))))
          ],
          .return (.binary .and (.unary .not (.binary .eq (.ident state) (.ident item)))
            (.unary .not (.ident item)))
        ]
      }]
      exports := #[{ localName := evaluate, exportName := evaluate }] }
  let negatedSource ← print .compact negated
  unless negatedSource ==
      "function evaluate(state,item){if(state!==item){return state+(item!==1);}return state!==item&&!item;}export{evaluate};" do
    throw <| IO.userError s!"negated equality golden changed: {negatedSource}"
  let invalid : Module :=
    { declarations := #[]
      exports := #[{ localName := evaluate, exportName := evaluate }] }
  match Printer.module .readable invalid with
  | .ok _ => throw <| IO.userError "printer emitted an invalid JavaScript AST"
  | .error error =>
      unless error.code == "LRX-BE-011" do
        throw <| IO.userError "printer returned the wrong validation diagnostic"

end LeanRxTest.Backend.JsPrinter
