import LeanRx.Backend.JsAst

namespace LeanRx.Js

structure NameAllocator where
  used : List String := []
deriving Repr, BEq

namespace NameAllocator

private def isAsciiLetter (char : Char) : Bool :=
  ('a' ≤ char && char ≤ 'z') || ('A' ≤ char && char ≤ 'Z')

private def isAsciiDigit (char : Char) : Bool :=
  '0' ≤ char && char ≤ '9'

private def allowed (char : Char) : Bool :=
  isAsciiLetter char || isAsciiDigit char || char == '_' || char == '$'

private def sanitizeChar (char : Char) : Char :=
  if allowed char then char else '_'

def baseName (requested : String) : String :=
  let sanitized := String.ofList (requested.toList.map sanitizeChar)
  let nonempty := if sanitized.isEmpty then "value" else sanitized
  let started := match nonempty.toList with
    | first :: _ => if isAsciiDigit first then "_" ++ nonempty else nonempty
    | [] => "value"
  if Ident.valid started then started else started ++ "_"

private def candidate (base : String) : Nat → String
  | 0 => base
  | index + 1 => base ++ "_" ++ toString (index + 2)

private def firstUnused (used : List String) (base : String) : String :=
  let candidates := (List.range (used.length + 1)).map (candidate base)
  candidates.find? (fun value => ¬used.contains value)
    |>.getD (candidate base (used.length + 1))

def allocate (allocator : NameAllocator) (requested : String) :
    Except Error (Ident × NameAllocator) := do
  let raw := firstUnused allocator.used (baseName requested)
  let name ← Ident.checked raw
  pure (name, { used := allocator.used ++ [raw] })

end NameAllocator

end LeanRx.Js
