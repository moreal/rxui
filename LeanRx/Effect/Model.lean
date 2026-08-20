import LeanRx.Core.RuntimeRep

namespace LeanRx.Effect

/-- Stable command identity. Only the allocator API can advance identities. -/
structure Handle where
  private mk ::
  value : Nat
deriving Repr, BEq, DecidableEq

namespace Handle

def first : Handle := ⟨0⟩

def next (handle : Handle) : Handle := ⟨handle.value + 1⟩

def debug (handle : Handle) : String := s!"cmd-{handle.value}"

end Handle

structure Error where
  code : String
  message : String
deriving Repr, BEq

inductive StorageResult where
  | missing
  | found (value : String)
deriving Repr, BEq

inductive HttpMethod where
  | get
deriving Repr, BEq, DecidableEq

structure HttpRequest where
  method : HttpMethod := .get
  url : String
  query : Array (String × String) := #[]
deriving Repr, BEq

structure HttpResponse where
  status : UInt32
  body : String
deriving Repr, BEq

inductive PortMode where
  | sync
  | async
deriving Repr, BEq, DecidableEq

inductive PortCancellation where
  | none
  | owned
deriving Repr, BEq, DecidableEq

/-- Wire types for explicit foreign boundaries. Structured wire metadata is
kept separate from `RuntimeTypeId`, so it cannot enter reactive equality or the
scalar graph ABI. -/
inductive PortTypeId where
  | runtime (value : RuntimeTypeId)
  | array (element : PortTypeId)
  | record (name : String)
deriving Repr, BEq, DecidableEq

def PortTypeId.debug : PortTypeId → String
  | .runtime value => value.debug
  | .array element => s!"array<{element.debug}>"
  | .record name => s!"record<{name}>"

def PortMode.debug : PortMode → String
  | .sync => "sync"
  | .async => "async"

def PortCancellation.debug : PortCancellation → String
  | .none => "none"
  | .owned => "owned"

/-- A structured wire value has an explicit nominal layout name while retaining
its Lean payload type. The wrapper is erased by specialized backend lowering. -/
structure PortRecord (name : String) (α : Type) where
  value : α
deriving Repr

/-- Type-indexed evidence for foreign wire metadata. Callers cannot attach a
record/array descriptor to an unrelated Lean input or output type. -/
inductive PortRep : Type → Type 1 where
  | runtime (value : RuntimeType α) : PortRep α
  | array (element : PortRep α) : PortRep (Array α)
  | record (name : String) : PortRep (PortRecord name α)

def PortRep.typeId : {α : Type} → PortRep α → PortTypeId
  | _, .runtime value => .runtime value.id
  | _, .array element => .array element.typeId
  | _, .record name => .record name

/-- A typed foreign boundary. Construction requires explicit runtime
representations, operational metadata, trust/security notes, and a native mock.
It does not contain JavaScript source. -/
structure ForeignPort (ι ο : Type) where
  private mk ::
  name : String
  inputType : PortTypeId
  outputType : PortTypeId
  mode : PortMode
  cancellation : PortCancellation
  errors : Array String
  trust : String
  security : String
  nativeMock : ι → Except Error ο

namespace ForeignPort

def createStructured (name : String) (inputRep : PortRep ι) (outputRep : PortRep ο)
    (mode : PortMode) (cancellation : PortCancellation) (errors : Array String)
    (trust security : String) (nativeMock : ι → Except Error ο) :
    Except Error (ForeignPort ι ο) :=
  if name.isEmpty then .error {
    code := "LRX-PORT-101"
    message := "foreign port name must not be empty"
  } else if trust.isEmpty then .error {
    code := "LRX-PORT-102"
    message := s!"foreign port {name.quote} must declare its trust boundary"
  } else if security.isEmpty then .error {
    code := "LRX-PORT-103"
    message := s!"foreign port {name.quote} must declare security behavior"
  } else .ok {
    name
    inputType := inputRep.typeId
    outputType := outputRep.typeId
    mode
    cancellation
    errors
    trust
    security
    nativeMock
  }

def create [inputRuntime : RuntimeRep ι] [outputRuntime : RuntimeRep ο]
    (name : String) (mode : PortMode) (cancellation : PortCancellation)
    (errors : Array String) (trust security : String)
    (nativeMock : ι → Except Error ο) : Except Error (ForeignPort ι ο) :=
  createStructured name (.runtime inputRuntime.runtimeType)
    (.runtime outputRuntime.runtimeType) mode cancellation errors trust security nativeMock

def runMock (port : ForeignPort ι ο) (input : ι) : Except Error ο :=
  port.nativeMock input

end ForeignPort

end LeanRx.Effect
