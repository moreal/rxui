import LeanRx.Backend.JsAst

namespace LeanRx.Js.Printer

inductive Mode where
  | readable
  | compact
deriving Repr, BEq

private def hexDigit : Nat → String
  | 0 => "0" | 1 => "1" | 2 => "2" | 3 => "3"
  | 4 => "4" | 5 => "5" | 6 => "6" | 7 => "7"
  | 8 => "8" | 9 => "9" | 10 => "a" | 11 => "b"
  | 12 => "c" | 13 => "d" | 14 => "e" | _ => "f"

private def hex4 (value : Nat) : String :=
  hexDigit ((value / 4096) % 16) ++ hexDigit ((value / 256) % 16) ++
    hexDigit ((value / 16) % 16) ++ hexDigit (value % 16)

private def escapeChar (char : Char) : String :=
  match char with
  | '"' => "\\\""
  | '\\' => "\\\\"
  | '\x08' => "\\b"
  | '\x0c' => "\\f"
  | '\n' => "\\n"
  | '\r' => "\\r"
  | '\t' => "\\t"
  | char =>
      let code := char.toNat
      if code < 32 || code = 0x2028 || code = 0x2029 then "\\u" ++ hex4 code
      else char.toString

def stringLiteral (value : String) : String :=
  "\"" ++ String.join (value.toList.map escapeChar) ++ "\""

private def unaryOp : UnaryOp → String
  | .not => "!"
  | .neg => "-"

private def binaryOp : BinaryOp → String
  | .add => "+" | .sub => "-" | .mul => "*" | .rem => "%"
  | .eq => "===" | .lt => "<" | .le => "<="
  | .and => "&&" | .or => "||"

private def separator : Mode → String
  | .readable => " "
  | .compact => ""

def literal : Literal → String
  | .boolean true => "true"
  | .boolean false => "false"
  | .string value => stringLiteral value
  | .bigint value => if value < 0 then "(" ++ toString value ++ "n)" else toString value ++ "n"
  | .number value => toString value
  | .null => "null"

mutual
  def expr (mode : Mode) : Expr → Except Error String
    | .ident name => pure name.raw
    | .literal value => pure (literal value)
    | .unary op value => do
        pure <| "(" ++ unaryOp op ++ (← expr mode value) ++ ")"
    | .binary op left right => do
        let space := separator mode
        pure <| "(" ++ (← expr mode left) ++ space ++ binaryOp op ++ space ++
          (← expr mode right) ++ ")"
    | .conditional condition yes no => do
        let space := separator mode
        pure <| "(" ++ (← expr mode condition) ++ space ++ "?" ++ space ++
          (← expr mode yes) ++ space ++ ":" ++ space ++ (← expr mode no) ++ ")"
    | .call callee args => do
        pure <| (← expr mode callee) ++ "(" ++
          String.intercalate (if mode == .readable then ", " else ",")
            (← exprArgs mode args) ++ ")"

  def exprArgs (mode : Mode) : Args → Except Error (List String)
    | .nil => pure []
    | .cons head tail => do pure ((← expr mode head) :: (← exprArgs mode tail))
end

private def indent (depth : Nat) : String :=
  String.join (List.replicate (depth * 2) " ")

private def stmt (mode : Mode) (depth : Nat) : Stmt → Except Error String
  | .const name value => do
      let rendered ← expr mode value
      pure <| match mode with
        | .readable => indent depth ++ "const " ++ name.raw ++ " = " ++ rendered ++ ";"
        | .compact => "const " ++ name.raw ++ "=" ++ rendered ++ ";"
  | .expr value => do
      pure <| (if mode == .readable then indent depth else "") ++ (← expr mode value) ++ ";"
  | .return value => do
      let rendered ← expr mode value
      pure <| match mode with
        | .readable => indent depth ++ "return " ++ rendered ++ ";"
        | .compact => "return " ++ rendered ++ ";"

private def functionDecl (mode : Mode) (value : Function) : Except Error String := do
  let params := String.intercalate (if mode == .readable then ", " else ",") <|
    value.params.toList.map (·.raw)
  let body ← value.body.toList.mapM (stmt mode (if mode == .readable then 1 else 0))
  pure <| match mode with
  | .readable =>
      "function " ++ value.name.raw ++ "(" ++ params ++ ") {\n" ++
        String.intercalate "\n" body ++ "\n}"
  | .compact =>
      "function " ++ value.name.raw ++ "(" ++ params ++ "){" ++
        String.join body ++ "}"

private def decl (mode : Mode) : Decl → Except Error String
  | .function value => functionDecl mode value

private def importEntry (mode : Mode) (entry : Import) : String :=
  let names := entry.names.toList.map fun (remote, localName) =>
    if remote == localName then remote.raw else remote.raw ++ " as " ++ localName.raw
  match mode with
  | .readable =>
      "import { " ++ String.intercalate ", " names ++ " } from " ++
        stringLiteral entry.source ++ ";"
  | .compact =>
      "import{" ++ String.intercalate "," names ++ "}from" ++ stringLiteral entry.source ++ ";"

private def exportEntry (mode : Mode) (entry : Export) : String :=
  let name := if entry.localName == entry.exportName then entry.localName.raw
    else entry.localName.raw ++ " as " ++ entry.exportName.raw
  match mode with
  | .readable => "export { " ++ name ++ " };"
  | .compact => "export{" ++ name ++ "};"

def module (mode : Mode) (value : Module) : Except Error String := do
  value.validate
  let declarations ← value.declarations.toList.mapM (decl mode)
  let rendered := value.imports.toList.map (importEntry mode) ++ declarations ++
    value.exports.toList.map (exportEntry mode)
  pure <| match mode with
    | .readable => String.intercalate "\n" rendered ++ "\n"
    | .compact => String.join rendered

end LeanRx.Js.Printer
