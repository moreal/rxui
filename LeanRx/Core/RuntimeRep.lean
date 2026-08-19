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

/-- Closed runtime codes. A code's index fixes its JavaScript ABI. Indexed
lengths and bounds are compile-time evidence and are not stored in values. -/
inductive RuntimeType : Type → Type 1 where
  | bool : RuntimeType Bool
  | string : RuntimeType String
  | int : RuntimeType Int
  | nat : RuntimeType Nat
  | vector (element : RuntimeType α) (length : Nat) : RuntimeType (Vector α length)
  | fin (bound : Nat) : RuntimeType (Fin bound)

/-- Erased runtime type identity retained by graph and backend validation. -/
inductive RuntimeTypeId where
  | bool
  | string
  | int
  | nat
  | vector (element : RuntimeTypeId) (length : Nat)
  | fin (bound : Nat)
  | record (name : String)
  | list (element : RuntimeTypeId)
deriving Repr, BEq, DecidableEq, Ord

def RuntimeType.id : {α : Type} → RuntimeType α → RuntimeTypeId
  | _, .bool => .bool
  | _, .string => .string
  | _, .int => .int
  | _, .nat => .nat
  | _, .vector element length => .vector element.id length
  | _, .fin bound => .fin bound

/-- Stable erased runtime type spelling used by diagnostics and manifests. -/
def RuntimeTypeId.debug : RuntimeTypeId → String
  | .bool => "bool"
  | .string => "string"
  | .int => "int"
  | .nat => "nat"
  | .vector element length => s!"vector<{element.debug},{length}>"
  | .fin bound => s!"fin<{bound}>"
  | .record name => s!"record<{name}>"
  | .list element => s!"list<{element.debug}>"

def RuntimeType.jsType : {α : Type} → RuntimeType α → JsType
  | _, .bool => .boolean
  | _, .string => .string
  | _, .int => .bigint
  | _, .nat => .bigint
  | _, .vector element _ => .array element.jsType
  | _, .fin _ => .number

/-- Whether this representation removes static proof/index evidence. This is
metadata for the erasure checker; generated code must never branch on it. -/
def RuntimeType.erasesProofs : {α : Type} → RuntimeType α → Bool
  | _, .bool | _, .string | _, .int | _, .nat => false
  | _, .vector _ _ | _, .fin _ => true

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

/-- Vectors cross the boundary as arrays. Their length and constructor proof
are compile-time evidence and are absent from the JavaScript value. -/
instance [element : RuntimeRep α] : RuntimeRep (Vector α length) where
  runtimeType := .vector element.runtimeType length

/-- Finite indices cross the boundary as JavaScript numbers. The bound proof is
erased; only constructors checked by Lean may introduce values. -/
instance : RuntimeRep (Fin bound) where
  runtimeType := .fin bound

def RuntimeRep.jsType (α : Type) [rep : RuntimeRep α] : JsType :=
  rep.runtimeType.jsType

def RuntimeRep.typeId (α : Type) [rep : RuntimeRep α] : RuntimeTypeId :=
  rep.runtimeType.id

def RuntimeRep.erasesProofs (α : Type) [rep : RuntimeRep α] : Bool :=
  rep.runtimeType.erasesProofs

/-- Stable human-readable representation metadata for diagnostics/manifests. -/
def RuntimeRep.debug (α : Type) [RuntimeRep α] : String :=
  (RuntimeRep.jsType α).debug

end LeanRx
