namespace LeanRx

/-- A deterministic source position used in diagnostics and IR.

`line` and `column` are one-based for original source and zero only for generated
source. `byteOffset` is a zero-based UTF-8 byte offset. -/
structure SourcePos where
  line : Nat
  column : Nat
  byteOffset : Nat
deriving Repr, BEq, DecidableEq

/-- A half-open source span by byte offset. `file` is a normalized,
project-relative path; an empty file marks generated or unavailable source. -/
structure SourceSpan where
  file : String
  start : SourcePos
  stop : SourcePos
deriving Repr, BEq, DecidableEq

/-- Source information for declarations synthesized without user syntax. -/
def SourceSpan.generated : SourceSpan :=
  { file := ""
    start := { line := 0, column := 0, byteOffset := 0 }
    stop := { line := 0, column := 0, byteOffset := 0 } }

end LeanRx
