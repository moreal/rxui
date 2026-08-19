namespace LeanRx.Js

structure Error where
  code : String
  message : String
deriving Repr, BEq

private def isAsciiLetter (char : Char) : Bool :=
  ('a' ≤ char && char ≤ 'z') || ('A' ≤ char && char ≤ 'Z')

private def isAsciiDigit (char : Char) : Bool :=
  '0' ≤ char && char ≤ '9'

private def isIdentifierStart (char : Char) : Bool :=
  isAsciiLetter char || char == '_' || char == '$'

private def isIdentifierContinue (char : Char) : Bool :=
  isIdentifierStart char || isAsciiDigit char

private def reserved : List String := [
  "await", "break", "case", "catch", "class", "const", "continue", "debugger",
  "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally",
  "for", "function", "if", "import", "in", "instanceof", "let", "new", "null",
  "return", "static", "super", "switch", "this", "throw", "true", "try",
  "typeof", "var", "void", "while", "with", "yield", "implements", "interface",
  "package", "private", "protected", "public", "eval", "arguments", "Function"
]

structure Ident where
  private mk ::
  raw : String
deriving Repr, BEq, DecidableEq, Ord

namespace Ident

def valid (value : String) : Bool :=
  match value.toList with
  | [] => false
  | first :: rest =>
      isIdentifierStart first && rest.all isIdentifierContinue && ¬reserved.contains value

def checked (value : String) : Except Error Ident :=
  if valid value then .ok ⟨value⟩
  else .error { code := "LRX-BE-001", message := s!"invalid JavaScript identifier: {value}" }

end Ident

inductive Literal where
  | boolean (value : Bool)
  | string (value : String)
  | bigint (value : Int)
  | number (value : UInt32)
  | signedIntegerPattern
  | naturalPattern
  | asciiTrimPattern
  | null
deriving Repr, BEq

inductive UnaryOp where
  | not
  | neg
deriving Repr, BEq

inductive BinaryOp where
  | add | sub | mul | div | rem
  | eq | lt | le
  | and | or
deriving Repr, BEq

mutual
  inductive Expr where
    | ident (name : Ident)
    | literal (value : Literal)
    | unary (op : UnaryOp) (value : Expr)
    | binary (op : BinaryOp) (left right : Expr)
    | conditional (condition yes no : Expr)
    | call (callee : Expr) (args : Args)
    | array (values : Args)
    | index (target index : Expr)
  deriving Repr, BEq

  inductive Args where
    | nil
    | cons (head : Expr) (tail : Args)
  deriving Repr, BEq
end

namespace Args

def ofList : List Expr → Args
  | [] => .nil
  | head :: tail => .cons head (ofList tail)

end Args

inductive AssignTarget where
  | ident (name : Ident)
  | index (target index : Expr)
deriving Repr, BEq

mutual
  inductive Stmt where
    | const (name : Ident) (value : Expr)
    | assign (target : AssignTarget) (value : Expr)
    | expr (value : Expr)
    | ifThen (condition : Expr) (body : Block)
    | forOf (binding : Ident) (iterable : Expr) (body : Block)
    | return (value : Expr)
  deriving Repr, BEq

  inductive Block where
    | nil
    | cons (head : Stmt) (tail : Block)
  deriving Repr, BEq
end

namespace Block

def ofList : List Stmt → Block
  | [] => .nil
  | head :: tail => .cons head (ofList tail)

end Block

structure Function where
  name : Ident
  params : Array Ident
  body : Array Stmt
deriving Repr, BEq

inductive Decl where
  | function (value : Function)
deriving Repr, BEq

namespace Decl

def name : Decl → Ident
  | .function value => value.name

end Decl

structure Import where
  source : String
  names : Array (Ident × Ident)
deriving Repr, BEq

structure Export where
  localName : Ident
  exportName : Ident
deriving Repr, BEq

structure Module where
  globals : Array Ident := #[]
  imports : Array Import := #[]
  declarations : Array Decl
  exports : Array Export
deriving Repr, BEq

namespace Module

private def duplicate? [BEq α] (values : List α) : Bool :=
  match values with
  | [] => false
  | value :: rest => rest.contains value || duplicate? rest

private def importLocals (module : Module) : List Ident :=
  module.imports.toList.flatMap fun entry => entry.names.toList.map (·.2)

private def declarationNames (module : Module) : List Ident :=
  module.declarations.toList.map Decl.name

private def constNames (body : List Stmt) : List Ident :=
  body.filterMap fun statement => match statement with
    | .const name _ => some name
    | _ => none

private def blockConstNames : Block → List Ident
  | .nil => []
  | .cons (.const name _) tail => name :: blockConstNames tail
  | .cons _ tail => blockConstNames tail

mutual
  private def exprBound (bound : List Ident) : Expr → Bool
    | .ident name => bound.contains name
    | .literal _ => true
    | .unary _ value => exprBound bound value
    | .binary _ left right => exprBound bound left && exprBound bound right
    | .conditional condition yes no =>
        exprBound bound condition && exprBound bound yes && exprBound bound no
    | .call callee args => exprBound bound callee && argsBound bound args
    | .array values => argsBound bound values
    | .index target index => exprBound bound target && exprBound bound index

  private def argsBound (bound : List Ident) : Args → Bool
    | .nil => true
    | .cons head tail => exprBound bound head && argsBound bound tail
end

mutual
  private def stmtBound (bound : List Ident) : Stmt → Bool
    | .const _ value => exprBound bound value
    | .assign target value => assignTargetBound bound target && exprBound bound value
    | .expr value => exprBound bound value
    | .ifThen condition body => exprBound bound condition && blockBound bound body
    | .forOf binding iterable body =>
        ¬bound.contains binding && exprBound bound iterable && blockBound (binding :: bound) body
    | .return value => exprBound bound value

  private def assignTargetBound (bound : List Ident) : AssignTarget → Bool
    | .ident name => bound.contains name
    | .index target index => exprBound bound target && exprBound bound index

  private def blockBound (outer : List Ident) (body : Block) : Bool :=
    let locals := blockConstNames body
    ¬duplicate? locals && ¬locals.any outer.contains && blockStatementsBound (outer ++ locals) body

  private def blockStatementsBound (bound : List Ident) : Block → Bool
    | .nil => true
    | .cons head tail => stmtBound bound head && blockStatementsBound bound tail
end

def validate (module : Module) : Except Error Unit := do
  for entry in module.imports do
    if entry.source.isEmpty then
      throw { code := "LRX-BE-002", message := "JavaScript import source must not be empty" }
    if entry.names.isEmpty then
      throw { code := "LRX-BE-003", message := "JavaScript import must bind at least one name" }
    if duplicate? (entry.names.toList.map (·.2)) then
      throw { code := "LRX-BE-004", message := "JavaScript import has duplicate local bindings" }
  let imported := importLocals module
  let declared := declarationNames module
  let globals := module.globals.toList
  if duplicate? globals then
    throw { code := "LRX-BE-016", message := "JavaScript module has duplicate globals" }
  if duplicate? imported then
    throw { code := "LRX-BE-005", message := "JavaScript imports collide on a local binding" }
  if duplicate? declared then
    throw { code := "LRX-BE-006", message := "JavaScript declarations have duplicate names" }
  if imported.any declared.contains then
    throw { code := "LRX-BE-007", message := "JavaScript import and declaration names collide" }
  if globals.any (fun name => imported.contains name || declared.contains name) then
    throw { code := "LRX-BE-017", message := "JavaScript global collides with a module binding" }
  for declaration in module.declarations do
    match declaration with
    | .function value =>
        if duplicate? value.params.toList then
          throw { code := "LRX-BE-008", message := "JavaScript function has duplicate parameters" }
        if value.body.isEmpty then
          throw { code := "LRX-BE-009", message := "JavaScript function body must not be empty" }
        let locals := constNames value.body.toList
        if duplicate? locals || value.params.toList.any locals.contains then
          throw { code := "LRX-BE-016", message := "JavaScript function has colliding lexical bindings" }
        if globals.any (fun name => value.params.toList.contains name || locals.contains name) then
          throw { code := "LRX-BE-017", message := "JavaScript function shadows a declared global" }
        let bound := globals ++ imported ++ declared ++ value.params.toList ++ locals
        unless value.body.toList.all (stmtBound bound) do
          throw {
            code := "LRX-BE-018"
            message := "JavaScript function has an unbound identifier or invalid nested lexical scope"
          }
  if duplicate? (module.exports.toList.map (·.exportName)) then
    throw { code := "LRX-BE-010", message := "JavaScript module has duplicate export names" }
  let bound := imported ++ declared
  for entry in module.exports do
    unless bound.contains entry.localName do
      throw { code := "LRX-BE-011", message := "JavaScript export references an unbound local" }

end Module

end LeanRx.Js
