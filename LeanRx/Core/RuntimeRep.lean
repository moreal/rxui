namespace LeanRx

/-- Browser-side runtime categories owned by the custom Reactive IR backend. -/
inductive JsType where
  | boolean
  | string
  | bigint
  | number
  | array (element : JsType)
  | object (name : String)
deriving Repr, BEq, DecidableEq

/-- Explicit evidence that a Lean value may cross the browser boundary. -/
class RuntimeRep (α : Type u) where
  jsType : JsType
  eraseProofs : Bool := false

instance : RuntimeRep Bool where
  jsType := .boolean

instance : RuntimeRep String where
  jsType := .string

/-- Unbounded Lean integers use JavaScript BigInt, never Number. -/
instance : RuntimeRep Int where
  jsType := .bigint

/-- Naturals use non-negative JavaScript BigInt. -/
instance : RuntimeRep Nat where
  jsType := .bigint

/-- Stable human-readable representation metadata for diagnostics/manifests. -/
def RuntimeRep.debug (α : Type u) [rep : RuntimeRep α] : String :=
  let kind := match rep.jsType with
    | .boolean => "boolean"
    | .string => "string"
    | .bigint => "bigint"
    | .number => "number"
    | .array _ => "array"
    | .object name => "object:" ++ name
  if rep.eraseProofs then kind ++ ":erased" else kind

end LeanRx
