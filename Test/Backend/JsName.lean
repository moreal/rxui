import LeanRx.Backend.JsName

namespace LeanRxTest.Backend.JsName

open LeanRx.Js

private def mustAllocate (allocator : NameAllocator) (requested : String) :
    IO (Ident × NameAllocator) :=
  match allocator.allocate requested with
  | .ok result => pure result
  | .error error => throw <| IO.userError s!"name allocation failed: {error.message}"

def run : IO Unit := do
  let (first, allocator) ← mustAllocate {} "value"
  let (second, allocator) ← mustAllocate allocator "value"
  let (third, allocator) ← mustAllocate allocator "value"
  let (keyword, allocator) ← mustAllocate allocator "class"
  let (strictKeyword, allocator) ← mustAllocate allocator "enum"
  let (dynamicCode, allocator) ← mustAllocate allocator "eval"
  let (numeric, allocator) ← mustAllocate allocator "2d"
  let (punctuation, allocator) ← mustAllocate allocator "has-dash"
  let (unicode, _) ← mustAllocate allocator "린Rx"
  unless [first.raw, second.raw, third.raw] == ["value", "value_2", "value_3"] do
    throw <| IO.userError "identifier collision suffixes changed"
  unless keyword.raw == "class_" && strictKeyword.raw == "enum_" &&
      dynamicCode.raw == "eval_" && numeric.raw == "_2d" &&
      punctuation.raw == "has_dash" && unicode.raw == "_Rx" do
    throw <| IO.userError "identifier mangling changed"
  let replay ← mustAllocate {} "value"
  unless replay.1 == first do
    throw <| IO.userError "identifier allocation is not replay deterministic"

end LeanRxTest.Backend.JsName
