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

/-- A typed foreign boundary. Construction requires explicit runtime
representations, operational metadata, trust/security notes, and a native mock.
It does not contain JavaScript source. -/
structure ForeignPort (ι ο : Type) where
  private mk ::
  name : String
  inputRuntime : RuntimeRep ι
  outputRuntime : RuntimeRep ο
  mode : PortMode
  cancellation : PortCancellation
  errors : Array String
  trust : String
  security : String
  nativeMock : ι → Except Error ο

namespace ForeignPort

def create [inputRuntime : RuntimeRep ι] [outputRuntime : RuntimeRep ο]
    (name : String) (mode : PortMode) (cancellation : PortCancellation)
    (errors : Array String) (trust security : String)
    (nativeMock : ι → Except Error ο) : Except Error (ForeignPort ι ο) :=
  if name.isEmpty then .error {
    code := "LRX-PORT-001"
    message := "foreign port name must not be empty"
  } else if trust.isEmpty then .error {
    code := "LRX-PORT-002"
    message := s!"foreign port {name.quote} must declare its trust boundary"
  } else if security.isEmpty then .error {
    code := "LRX-PORT-003"
    message := s!"foreign port {name.quote} must declare security behavior"
  } else .ok {
    name
    inputRuntime
    outputRuntime
    mode
    cancellation
    errors
    trust
    security
    nativeMock
  }

def inputType (port : ForeignPort ι ο) : RuntimeTypeId :=
  port.inputRuntime.runtimeType.id

def outputType (port : ForeignPort ι ο) : RuntimeTypeId :=
  port.outputRuntime.runtimeType.id

def runMock (port : ForeignPort ι ο) (input : ι) : Except Error ο :=
  port.nativeMock input

end ForeignPort

end LeanRx.Effect
