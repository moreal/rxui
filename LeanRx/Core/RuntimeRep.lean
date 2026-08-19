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

/-- Stable recursive runtime-type rendering for diagnostics and manifests. -/
def JsType.debug : JsType → String
  | .boolean => "boolean"
  | .string => "string"
  | .bigint => "bigint"
  | .number => "number"
  | .array element => "array<" ++ element.debug ++ ">"
  | .object name => "object(" ++ name.quote ++ ")"

/-- Closed scalar runtime codes. A code's index fixes its JavaScript ABI. -/
inductive RuntimeType : Type → Type 1 where
  | bool : RuntimeType Bool
  | string : RuntimeType String
  | int : RuntimeType Int
  | nat : RuntimeType Nat

def RuntimeType.jsType : {α : Type} → RuntimeType α → JsType
  | _, .bool => .boolean
  | _, .string => .string
  | _, .int => .bigint
  | _, .nat => .bigint

/-- Explicit evidence that a Lean value may cross the browser boundary.

The indexed runtime code prevents local instances from remapping `Int` or `Nat`
to JavaScript Number. -/
class RuntimeRep (α : Type) where
  runtimeType : RuntimeType α

instance : RuntimeRep Bool where
  runtimeType := .bool

instance : RuntimeRep String where
  runtimeType := .string

/-- Unbounded Lean integers use JavaScript BigInt, never Number. -/
instance : RuntimeRep Int where
  runtimeType := .int

/-- Naturals use non-negative JavaScript BigInt. -/
instance : RuntimeRep Nat where
  runtimeType := .nat

def RuntimeRep.jsType (α : Type) [rep : RuntimeRep α] : JsType :=
  rep.runtimeType.jsType

/-- Stable human-readable representation metadata for diagnostics/manifests. -/
def RuntimeRep.debug (α : Type) [RuntimeRep α] : String :=
  (RuntimeRep.jsType α).debug

end LeanRx
