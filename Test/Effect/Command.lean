import LeanRx.Effect.Command

namespace LeanRxTest.Effect.Command

open LeanRx.Effect

private inductive Msg where
  | timer
  | read (result : Except Error StorageResult)
  | wrote (result : Except Error Unit)
  | fetched (result : Except Error HttpResponse)
  | ported (result : Except Error String)
deriving Repr

private def assertTrue (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Deterministic test double covering every `Cmd` constructor. -/
private structure MockHost where
  storage : List (String × String) := []
  storageReadFailures : List String := []
  storageWriteFailures : List String := []
  http : HttpRequest → Except Error HttpResponse
  cancelled : List Handle := []

private structure MockResult where
  host : MockHost
  messages : List Msg
  trace : List String

private def storageValue (host : MockHost) (key : String) : Option String :=
  host.storage.find? (·.1 == key) |>.map (·.2)

private def setStorage (host : MockHost) (key value : String) : MockHost :=
  { host with storage := (key, value) :: host.storage.filter (·.1 != key) }

private def isCancelled (host : MockHost) (handle : Handle) : Bool :=
  host.cancelled.contains handle

private def append (left right : MockResult) : MockResult :=
  { host := right.host
    messages := left.messages ++ right.messages
    trace := left.trace ++ right.trace }

private def suppressed (host : MockHost) (handle : Handle) : MockResult :=
  { host, messages := [], trace := [s!"suppressed:{handle.debug}"] }

private def runMock (host : MockHost) : Cmd Msg → MockResult
  | .none => { host, messages := [], trace := ["none"] }
  | .batch commands =>
      commands.foldl (fun result command =>
        append result (runMock result.host command))
        { host, messages := [], trace := ["batch"] }
  | .timeout handle _ message =>
      if isCancelled host handle then suppressed host handle else
        { host, messages := [message], trace := [s!"timeout:{handle.debug}"] }
  | .storageGet handle key onResult =>
      if isCancelled host handle then suppressed host handle else
        let result : Except Error StorageResult :=
          if host.storageReadFailures.contains key then .error {
            code := "LRX-STORAGE-001"
            message := s!"mock storage read failed for {key.quote}"
          } else match storageValue host key with
          | none => .ok .missing
          | some value => .ok (.found value)
        { host
          messages := [onResult result]
          trace := [s!"storageGet:{handle.debug}:{key}"] }
  | .storageSet handle key value onResult =>
      if isCancelled host handle then suppressed host handle else
        if host.storageWriteFailures.contains key then
          { host
            messages := [onResult (.error {
              code := "LRX-STORAGE-002"
              message := s!"mock storage write failed for {key.quote}"
            })]
            trace := [s!"storageSet:error:{handle.debug}:{key}"] }
        else
          { host := setStorage host key value
            messages := [onResult (.ok ())]
            trace := [s!"storageSet:{handle.debug}:{key}"] }
  | .http handle request onResult =>
      if isCancelled host handle then suppressed host handle else
        { host
          messages := [onResult (host.http request)]
          trace := [s!"http:{handle.debug}:{request.url}"] }
  | .foreign handle port input onResult =>
      if isCancelled host handle then suppressed host handle else
        { host
          messages := [onResult (port.runMock input)]
          trace := [s!"foreign:{handle.debug}:{port.name}"] }
  | .cancel handle =>
      { host := { host with cancelled := handle :: host.cancelled }
        messages := []
        trace := [s!"cancel:{handle.debug}"] }

private def host : MockHost := {
  storage := [("notes", "saved")]
  http := fun request => .ok { status := 200, body := s!"response:{request.url}" }
}

private def uppercasePort : Except Error (ForeignPort String String) :=
  ForeignPort.create "uppercase" .sync .none #[]
    "native String.toUpper mock; browser adapter remains trusted"
    "text-only input/output; no markup or code execution"
    (fun value => .ok value.toUpper)

def run : IO Unit :=
  match uppercasePort with
  | .error error => throw <| IO.userError error.message
  | .ok port => do
      let first := Handle.first
      let second := first.next
      let third := second.next
      let fourth := third.next
      let fifth := fourth.next
      let command : Cmd Msg := .batch #[
        .storageGet first "notes" .read,
        .storageSet second "draft" "new" .wrote,
        .http third { url := "/issues?page=1" } .fetched,
        .foreign fourth port "leanrx" .ported,
        .cancel fifth,
        .timeout fifth 50 .timer
      ]
      let result := runMock host command
      assertTrue (result.messages.length == 4) "cancelled timer emitted a message"
      assertTrue (result.host.storage.contains ("draft", "new"))
        "storage test double did not persist the value"
      assertTrue (result.trace == ["batch", "storageGet:cmd-0:notes",
        "storageSet:cmd-1:draft", "http:cmd-2:/issues?page=1",
        "foreign:cmd-3:uppercase", "cancel:cmd-4", "suppressed:cmd-4"])
        "command test-double trace drifted"
      assertTrue (ForeignPort.inputType port == LeanRx.RuntimeTypeId.string &&
        ForeignPort.outputType port == LeanRx.RuntimeTypeId.string)
        "foreign port runtime signature drifted"
      assertTrue (match ForeignPort.create (ι := String) (ο := String) "" .sync .none #[]
          "trust" "security" .ok with
        | .error _ => true
        | .ok _ => false) "empty foreign port name was accepted"

end LeanRxTest.Effect.Command
