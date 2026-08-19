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
  "default", "delete", "do", "else", "export", "extends", "false", "finally",
  "for", "function", "if", "import", "in", "instanceof", "let", "new", "null",
  "return", "static", "super", "switch", "this", "throw", "true", "try",
  "typeof", "var", "void", "while", "with", "yield"
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
  else .error { code := "LRX-JS-001", message := s!"invalid JavaScript identifier: {value}" }

end Ident

inductive Literal where
  | boolean (value : Bool)
  | string (value : String)
  | bigint (value : Int)
  | number (value : Nat)
  | null
deriving Repr, BEq

inductive UnaryOp where
  | not
  | neg
deriving Repr, BEq

inductive BinaryOp where
  | add | sub | mul | rem
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

inductive Stmt where
  | const (name : Ident) (value : Expr)
  | expr (value : Expr)
  | return (value : Expr)
deriving Repr, BEq

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

def validate (module : Module) : Except Error Unit := do
  for entry in module.imports do
    if entry.source.isEmpty then
      throw { code := "LRX-JS-002", message := "JavaScript import source must not be empty" }
    if entry.names.isEmpty then
      throw { code := "LRX-JS-003", message := "JavaScript import must bind at least one name" }
    if duplicate? (entry.names.toList.map (·.2)) then
      throw { code := "LRX-JS-004", message := "JavaScript import has duplicate local bindings" }
  let imported := importLocals module
  let declared := declarationNames module
  if duplicate? imported then
    throw { code := "LRX-JS-005", message := "JavaScript imports collide on a local binding" }
  if duplicate? declared then
    throw { code := "LRX-JS-006", message := "JavaScript declarations have duplicate names" }
  if imported.any declared.contains then
    throw { code := "LRX-JS-007", message := "JavaScript import and declaration names collide" }
  for declaration in module.declarations do
    match declaration with
    | .function value =>
        if duplicate? value.params.toList then
          throw { code := "LRX-JS-008", message := "JavaScript function has duplicate parameters" }
        if value.body.isEmpty then
          throw { code := "LRX-JS-009", message := "JavaScript function body must not be empty" }
  if duplicate? (module.exports.toList.map (·.exportName)) then
    throw { code := "LRX-JS-010", message := "JavaScript module has duplicate export names" }
  let bound := imported ++ declared
  for entry in module.exports do
    unless bound.contains entry.localName do
      throw { code := "LRX-JS-011", message := "JavaScript export references an unbound local" }

end Module

end LeanRx.Js
