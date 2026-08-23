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
  | .add => "+" | .sub => "-" | .mul => "*" | .div => "/" | .rem => "%"
  | .eq => "===" | .lt => "<" | .le => "<="
  | .and => "&&" | .or => "||"

private def separator : Mode → String
  | .readable => " "
  | .compact => ""

def literal : Literal → String
  | .boolean true => "true"
  | .boolean false => "false"
  | .string value => stringLiteral value
  | .bigint value => toString value ++ "n"
  | .number value => toString value
  | .signedIntegerPattern => "/^-?[0-9]+$/"
  | .naturalPattern => "/^[0-9]+$/"
  | .asciiTrimPattern => "/^[ \\t\\r\\n]+|[ \\t\\r\\n]+$/g"
  | .null => "null"

/-- Binding strength of an operator position, higher binds tighter. The printer
wraps a sub-expression in parentheses only when its own strength is below the
strength its position requires, so the emitted text carries no redundant
parentheses; the levels follow the ECMAScript grammar for the forms the AST
models (conditional < `||` < `&&` < `===` < relational < additive <
multiplicative < prefix unary < call/member < primary). -/
private def conditionalPrecedence : Nat := 1
private def unaryPrecedence : Nat := 8
private def postfixPrecedence : Nat := 9
private def primaryPrecedence : Nat := 10

private def binaryPrecedence : BinaryOp → Nat
  | .or => 2
  | .and => 3
  | .eq => 4
  | .lt | .le => 5
  | .add | .sub => 6
  | .mul | .div | .rem => 7

private def precedence : Expr → Nat
  | .ident _ => primaryPrecedence
  | .literal (.bigint value) => if value < 0 then unaryPrecedence else primaryPrecedence
  | .literal _ => primaryPrecedence
  -- Printed as `left !== right` (see `expr`), so it binds like an equality.
  | .unary .not (.binary .eq _ _) => binaryPrecedence .eq
  | .unary _ _ => unaryPrecedence
  | .binary op _ _ => binaryPrecedence op
  | .conditional _ _ _ => conditionalPrecedence
  | .call _ _ | .index _ _ => postfixPrecedence
  | .array _ => primaryPrecedence

private def parenthesize (source : String) : String := "(" ++ source ++ ")"

private def startsWithMinus (source : String) : Bool :=
  source.startsWith "-"

/-- Wraps the rendering of `value` in parentheses when its own binding strength
is below the strength `minimum` that its position requires. -/
private def wrap (minimum : Nat) (value : Expr) (rendered : String) : String :=
  if precedence value < minimum then parenthesize rendered else rendered

mutual
  def expr (mode : Mode) : Expr → Except Error String
    | .ident name => pure name.raw
    | .literal value => pure (literal value)
    | .unary .not (.binary .eq left right) => do
        -- `!(a === b)` is `a !== b`: the same value for every operand pair, one
        -- token shorter and without the parentheses.
        let space := separator mode
        let level := binaryPrecedence .eq
        let renderedLeft := wrap level left (← expr mode left)
        let renderedRight := wrap (level + 1) right (← expr mode right)
        pure <| renderedLeft ++ space ++ "!==" ++ space ++ renderedRight
    | .unary op value => do
        let rendered := wrap unaryPrecedence value (← expr mode value)
        -- `- -x` would merge into a decrement; keep the inner negation grouped.
        let rendered := if op == .neg && startsWithMinus rendered then parenthesize rendered
          else rendered
        pure <| unaryOp op ++ rendered
    | .binary op left right => do
        let space := separator mode
        let level := binaryPrecedence op
        let renderedLeft := wrap level left (← expr mode left)
        let renderedRight := wrap (level + 1) right (← expr mode right)
        -- `a - -1` would merge into `a--1` in compact mode; keep the operand grouped.
        let renderedRight := if op == .sub && startsWithMinus renderedRight
          then parenthesize renderedRight else renderedRight
        pure <| renderedLeft ++ space ++ binaryOp op ++ space ++ renderedRight
    | .conditional condition yes no => do
        let space := separator mode
        pure <| wrap (conditionalPrecedence + 1) condition (← expr mode condition) ++ space ++
          "?" ++ space ++ wrap conditionalPrecedence yes (← expr mode yes) ++ space ++ ":" ++
          space ++ wrap conditionalPrecedence no (← expr mode no)
    | .call callee args => do
        pure <| wrap postfixPrecedence callee (← expr mode callee) ++ "(" ++
          String.intercalate (if mode == .readable then ", " else ",")
            (← exprArgs mode args) ++ ")"
    | .array values => do
        pure <| "[" ++ String.intercalate (if mode == .readable then ", " else ",")
          (← exprArgs mode values) ++ "]"
    | .index target index => do
        pure <| wrap postfixPrecedence target (← expr mode target) ++ "[" ++
          (← expr mode index) ++ "]"

  def exprArgs (mode : Mode) : Args → Except Error (List String)
    | .nil => pure []
    | .cons head tail => do pure ((← expr mode head) :: (← exprArgs mode tail))
end

private def indent (depth : Nat) : String :=
  String.join (List.replicate (depth * 2) " ")

private def assignTarget (mode : Mode) : AssignTarget → Except Error String
  | .ident name => pure name.raw
  | .index target index => do
      pure <| wrap postfixPrecedence target (← expr mode target) ++ "[" ++
        (← expr mode index) ++ "]"

/-- Whether evaluating `value` twice is indistinguishable from evaluating it
once: identifiers, literals, and index chains of those (no calls, nothing that
allocates). -/
private def pureReference : Expr → Bool
  | .ident _ | .literal _ => true
  | .index target index => pureReference target && pureReference index
  | _ => false

private def compoundOp : BinaryOp → Option String
  | .add => some "+=" | .sub => some "-=" | .mul => some "*="
  | .div => some "/=" | .rem => some "%="
  | _ => none

/-- `target = target op value` for an arithmetic `op` and a pure `target` prints
as the compound assignment `target op= value`; the reference is evaluated once
either way because a pure reference has no side effect to repeat. Returns the
operator and the right operand when the rewrite applies. -/
private def compoundAssignment (target : AssignTarget) (value : Expr) : Option (String × Expr) :=
  match value with
  | .binary op left right =>
      let reference : Expr := match target with
        | .ident name => .ident name
        | .index base index => .index base index
      match compoundOp op with
      | some operator =>
          if left == reference && pureReference reference then some (operator, right) else none
      | none => none
  | _ => none

mutual
  private def stmt (mode : Mode) (depth : Nat) : Stmt → Except Error String
  | .const name value => do
      let rendered ← expr mode value
      pure <| match mode with
        | .readable => indent depth ++ "const " ++ name.raw ++ " = " ++ rendered ++ ";"
        | .compact => "const " ++ name.raw ++ "=" ++ rendered ++ ";"
  | .assign target value => do
      let renderedTarget ← assignTarget mode target
      let (operator, value) := (compoundAssignment target value).getD ("=", value)
      let renderedValue ← expr mode value
      pure <| match mode with
        | .readable =>
            indent depth ++ renderedTarget ++ " " ++ operator ++ " " ++ renderedValue ++ ";"
        | .compact => renderedTarget ++ operator ++ renderedValue ++ ";"
  | .expr value => do
      pure <| (if mode == .readable then indent depth else "") ++ (← expr mode value) ++ ";"
  | .ifThen condition body => do
      let renderedCondition ← expr mode condition
      let renderedBody ← block mode (if mode == .readable then depth + 1 else depth) body
      pure <| match mode with
        | .readable => indent depth ++ "if (" ++ renderedCondition ++ ") {\n" ++
            String.intercalate "\n" renderedBody ++ "\n" ++ indent depth ++ "}"
        | .compact => "if(" ++ renderedCondition ++ "){" ++ String.join renderedBody ++ "}"
  | .forOf binding iterable body => do
      let renderedIterable ← expr mode iterable
      let renderedBody ← block mode (if mode == .readable then depth + 1 else depth) body
      pure <| match mode with
        | .readable => indent depth ++ "for (const " ++ binding.raw ++ " of " ++
            renderedIterable ++ ") {\n" ++ String.intercalate "\n" renderedBody ++
            "\n" ++ indent depth ++ "}"
        | .compact => "for(const " ++ binding.raw ++ " of " ++ renderedIterable ++ "){" ++
            String.join renderedBody ++ "}"
  | .return value => do
      let rendered ← expr mode value
      pure <| match mode with
        | .readable => indent depth ++ "return " ++ rendered ++ ";"
        | .compact => "return " ++ rendered ++ ";"

  private def block (mode : Mode) (depth : Nat) : Block → Except Error (List String)
    | .nil => pure []
    | .cons head tail => do pure ((← stmt mode depth head) :: (← block mode depth tail))
end

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
