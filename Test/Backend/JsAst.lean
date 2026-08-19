import LeanRx.Backend.JsAst

namespace LeanRxTest.Backend.JsAst

open LeanRx.Js

private def ident (value : String) : IO Ident :=
  match Ident.checked value with
  | .ok name => pure name
  | .error error => throw <| IO.userError error.message

private def expectError (code : String) (result : Except Error Unit) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"expected JavaScript AST error {code}"
  | .error error =>
      unless error.code == code do
        throw <| IO.userError s!"expected {code}, got {error.code}"

def run : IO Unit := do
  for value in ["value", "_value", "$value", "value2"] do
    match Ident.checked value with
    | .ok _ => pure ()
    | .error error => throw <| IO.userError s!"valid identifier rejected: {error.message}"
  for value in ["", "2value", "has-dash", "class", "enum", "implements", "interface",
      "package", "private", "protected", "public", "eval", "arguments", "Function", "한글"] do
    match Ident.checked value with
    | .error error =>
        unless error.code == "LRX-BE-001" do
          throw <| IO.userError "invalid identifier returned the wrong code"
    | .ok _ => throw <| IO.userError s!"invalid identifier accepted: {value}"
  let evaluate ← ident "evaluate"
  let input ← ident "input"
  let item ← ident "item"
  let stringGlobal ← ident "String"
  let valid : Module :=
    { declarations := #[.function {
        name := evaluate
        params := #[input]
        body := #[.return (.ident input)]
      }]
      exports := #[{ localName := evaluate, exportName := evaluate }] }
  match valid.validate with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"valid JavaScript AST rejected: {error.code}"
  let validLoop : Module :=
    { declarations := #[.function {
        name := evaluate
        params := #[input]
        body := #[
          .forOf item (.ident input) <| .ofList [.expr (.ident item)],
          .return (.ident input)
        ]
      }]
      exports := #[] }
  match validLoop.validate with
  | .ok _ => pure ()
  | .error error => throw <| IO.userError s!"valid for-of AST rejected: {error.code}"
  expectError "LRX-BE-006" ({
    declarations := #[
      .function { name := evaluate, params := #[], body := #[.return (.literal .null)] },
      .function { name := evaluate, params := #[], body := #[.return (.literal .null)] }
    ]
    exports := #[]
  } : Module).validate
  expectError "LRX-BE-008" ({
    declarations := #[.function {
      name := evaluate, params := #[input, input], body := #[.return (.ident input)]
    }]
    exports := #[]
  } : Module).validate
  expectError "LRX-BE-011" ({
    declarations := #[]
    exports := #[{ localName := evaluate, exportName := evaluate }]
  } : Module).validate
  expectError "LRX-BE-016" ({
    declarations := #[.function {
      name := evaluate
      params := #[]
      body := #[.const input (.literal .null), .const input (.literal .null)]
    }]
    exports := #[]
  } : Module).validate
  expectError "LRX-BE-016" ({
    declarations := #[.function {
      name := evaluate
      params := #[input]
      body := #[.const input (.literal .null), .return (.ident input)]
    }]
    exports := #[]
  } : Module).validate
  expectError "LRX-BE-018" ({
    declarations := #[.function {
      name := evaluate
      params := #[]
      body := #[.return (.ident input)]
    }]
    exports := #[]
  } : Module).validate
  expectError "LRX-BE-018" ({
    declarations := #[.function {
      name := evaluate
      params := #[input]
      body := #[.forOf input (.ident input) <| .ofList [.expr (.ident input)]]
    }]
    exports := #[]
  } : Module).validate
  expectError "LRX-BE-016" ({
    globals := #[stringGlobal, stringGlobal]
    declarations := #[.function {
      name := evaluate, params := #[], body := #[.return (.literal .null)]
    }]
    exports := #[]
  } : Module).validate
  expectError "LRX-BE-017" ({
    globals := #[stringGlobal]
    declarations := #[.function {
      name := evaluate, params := #[stringGlobal], body := #[.return (.ident stringGlobal)]
    }]
    exports := #[]
  } : Module).validate
  expectError "LRX-BE-018" ({
    declarations := #[.function {
      name := evaluate
      params := #[input]
      body := #[.ifThen (.literal (.boolean true)) <| .ofList [
        .const input (.literal .null)
      ]]
    }]
    exports := #[]
  } : Module).validate

end LeanRxTest.Backend.JsAst
