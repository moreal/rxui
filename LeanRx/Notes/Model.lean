import LeanRx.Effect.Command
import LeanRx.Effect.Resource

namespace LeanRx.Notes

open LeanRx.Effect

inductive Persistence where
  | idle
  | scheduled (handle : Handle)
  | saving (handle : Handle)
  | saved
  | failed (error : Error)
deriving Repr

inductive Msg where
  | restore
  | restored (handle : Handle) (result : Except Error StorageResult)
  | edit (value : String)
  | debounceFired (handle : Handle)
  | stored (handle : Handle) (result : Except Error Unit)
  | dispose
deriving Repr

structure State where
  private mk ::
  text : String
  restored : Resource String
  persistence : Persistence
  nextHandle : Handle
  disposed : Bool
deriving Repr

structure Transition where
  private mk ::
  state : State
  command : Cmd Msg

def initial : State := ⟨"", .idle, .idle, .first, false⟩

private def storageKey : String := "leanrx.notes"

private def allocate (state : State) : Handle × State :=
  (state.nextHandle, { state with nextHandle := state.nextHandle.next })

private def cancelPersistence : Persistence → Cmd Msg
  | .scheduled handle | .saving handle => .cancel handle
  | _ => .none

private def persistenceHandle : Persistence → Option Handle
  | .scheduled handle | .saving handle => some handle
  | _ => none

private def sameHandle (expected actual : Handle) : Bool := expected == actual

/-- Pure Notes reducer. It returns command data and never executes storage or
timer work. -/
def update (state : State) (message : Msg) : Transition :=
  if state.disposed then ⟨state, .none⟩ else
  match message with
  | .restore =>
      let (handle, next) := allocate state
      ⟨{ next with restored := .start handle },
        .storageGet handle storageKey (Msg.restored handle)⟩
  | .restored handle result =>
      match state.restored with
      | .loading active =>
          if sameHandle active handle then
            match result with
            | .ok .missing => ⟨{ state with restored := .success handle state.text }, .none⟩
            | .ok (.found value) =>
                ⟨{ state with text := value, restored := .success handle value }, .none⟩
            | .error error => ⟨{ state with restored := .failure handle error }, .none⟩
          else ⟨state, .none⟩
      | _ => ⟨state, .none⟩
  | .edit value =>
      let (restoreCancel, restored) := match state.restored with
        | .loading handle => (.cancel handle, .cancelled handle)
        | current => (.none, current)
      let previous := cancelPersistence state.persistence
      let (handle, next) := allocate state
      ⟨{ next with text := value, restored, persistence := .scheduled handle },
        .batch #[restoreCancel, previous, .timeout handle 250 (.debounceFired handle)]⟩
  | .debounceFired handle =>
      match state.persistence with
      | .scheduled active =>
          if sameHandle active handle then
            let (saveHandle, next) := allocate state
            ⟨{ next with persistence := .saving saveHandle },
              .storageSet saveHandle storageKey state.text (Msg.stored saveHandle)⟩
          else ⟨state, .none⟩
      | _ => ⟨state, .none⟩
  | .stored handle result =>
      match state.persistence with
      | .saving active =>
          if sameHandle active handle then
            match result with
            | .ok _ => ⟨{ state with persistence := .saved }, .none⟩
            | .error error => ⟨{ state with persistence := .failed error }, .none⟩
          else ⟨state, .none⟩
      | _ => ⟨state, .none⟩
  | .dispose =>
      let restoreCancel := match state.restored with
        | .loading handle => .cancel handle
        | _ => .none
      ⟨{ state with disposed := true },
        .batch #[restoreCancel, cancelPersistence state.persistence]⟩

def statusText (state : State) : String :=
  match state.restored with
  | .failure _ error => s!"Restore failed: {error.message}"
  | _ => match state.persistence with
    | .idle => "Not saved"
    | .scheduled _ => "Waiting to save"
    | .saving _ => "Saving"
    | .saved => "Saved"
    | .failed error => s!"Save failed: {error.message}"

def pendingHandle (state : State) : Option Handle :=
  persistenceHandle state.persistence

structure Spec where
  private mk ::
  name : String

namespace Spec

def create (name : String) : Spec := ⟨name⟩

structure Checked where
  private mk ::
  spec : Spec
  initial : State

def check (spec : Spec) : Except Error Checked :=
  if spec.name.isEmpty then .error {
    code := "LRX-EFFECT-001"
    message := "Notes component name must not be empty"
  } else .ok ⟨spec, Notes.initial⟩

end Spec

end LeanRx.Notes
