import Lean.Data.Json.Parser
import LeanRx.Effect.Command
import LeanRx.Effect.Resource

namespace LeanRx.IssueBrowser

open LeanRx.Effect

structure Issue where
  id : Nat
  title : String
deriving Repr, BEq

structure Page where
  issues : Array Issue
  hasMore : Bool
deriving Repr, BEq

structure RequestKey where
  handle : Handle
  query : String
  page : Nat
deriving Repr, BEq

inductive Msg where
  | setQuery (query : String)
  | search
  | nextPage
  | retry
  | received (key : RequestKey) (result : Except Error Page)
  | dispose
deriving Repr

structure State where
  private mk ::
  query : String
  issues : Array Issue
  currentPage : Nat
  hasMore : Bool
  resource : Resource Page
  active : Option RequestKey
  lastRequest : Option (String × Nat)
  nextHandle : Handle
  disposed : Bool
deriving Repr

structure Transition where
  private mk ::
  state : State
  command : Cmd Msg

def initial : State := ⟨"lean", #[], 0, false, .idle, none, none, .first, false⟩

private def decodeError (message : String) : Error := {
  code := "LRX-HTTP-DECODE-001"
  message := s!"issue response decode failed: {message}"
}

private def decodeIssue (value : Lean.Json) : Except Error Issue := do
  let idValue ← value.getObjVal? "id" |>.mapError decodeError
  let titleValue ← value.getObjVal? "title" |>.mapError decodeError
  let id ← idValue.getNat? |>.mapError decodeError
  let title ← titleValue.getStr? |>.mapError decodeError
  pure { id, title }

def decodePage (body : String) : Except Error Page := do
  let json ← Lean.Json.parse body |>.mapError decodeError
  let issuesValue ← json.getObjVal? "issues" |>.mapError decodeError
  let hasMoreValue ← json.getObjVal? "hasMore" |>.mapError decodeError
  let rawIssues ← issuesValue.getArr? |>.mapError decodeError
  let issues ← rawIssues.mapM decodeIssue
  let hasMore ← hasMoreValue.getBool? |>.mapError decodeError
  pure { issues, hasMore }

/-- Explicit browser JSON-decoder port. Its structured output is wire metadata,
not a reactive runtime/equality type. -/
def decoderPort : Except Error (ForeignPort String Page) :=
  ForeignPort.createStructured "decodeIssuePage" (.runtime .string)
    (.record "IssuePage") .sync .none
    #["LRX-HTTP-DECODE-001"]
    "browser JSON parsing and object validation remain in the backend TCB"
    "JSON is parsed as data; titles are returned as strings and never HTML"
    decodePage

def decodeResponse : Except Error HttpResponse → Except Error Page
  | .error error => .error error
  | .ok response =>
      if response.status == 200 then decodePage response.body
      else .error {
        code := "LRX-HTTP-STATUS-001"
        message := s!"issue request returned HTTP {response.status.toNat}"
      }

private def request (query : String) (page : Nat) : HttpRequest := {
  url := "/api/issues"
  query := #[
    ("q", query),
    ("page", toString page)
  ]
}

private def activeCancel (state : State) : Cmd Msg :=
  match state.active with
  | some key => .cancel key.handle
  | none => .none

private def beginRequest (state : State) (query : String) (page : Nat) : Transition :=
  let handle := state.nextHandle
  let key : RequestKey := { handle, query, page }
  let previous := activeCancel state
  ⟨{ state with
      query
      resource := .start handle
      active := some key
      lastRequest := some (query, page)
      nextHandle := handle.next },
    .batch #[previous, .http handle (request query page)
      (fun result => .received key (decodeResponse result))]⟩

private def sameRequest (left right : RequestKey) : Bool :=
  left.handle == right.handle && left.query == right.query && left.page == right.page

/-- Pure Issue Browser reducer. HTTP, decoding delivery, and cancellation are
commands/results at the boundary; no request executes here. -/
def update (state : State) (message : Msg) : Transition :=
  if state.disposed then ⟨state, .none⟩ else
  match message with
  | .setQuery query => beginRequest state query 1
  | .search => beginRequest state state.query 1
  | .nextPage =>
      if state.hasMore then beginRequest state state.query (state.currentPage + 1)
      else ⟨state, .none⟩
  | .retry =>
      match state.lastRequest with
      | some (query, page) => beginRequest state query page
      | none => beginRequest state state.query 1
  | .received key result =>
      match state.active with
      | some active =>
          if sameRequest active key then
            match result with
            | .ok page =>
                let issues := if key.page == 1 then page.issues else state.issues ++ page.issues
                ⟨{ state with
                    issues
                    currentPage := key.page
                    hasMore := page.hasMore
                    resource := .success key.handle page
                    active := none }, .none⟩
            | .error error =>
                ⟨{ state with resource := .failure key.handle error, active := none }, .none⟩
          else ⟨state, .none⟩
      | none => ⟨state, .none⟩
  | .dispose =>
      ⟨{ state with
          resource := match state.active with
            | some key => .cancelled key.handle
            | none => state.resource
          active := none
          disposed := true }, activeCancel state⟩

def statusText (state : State) : String :=
  match state.resource with
  | .idle => "Idle"
  | .loading _ => "Loading"
  | .success _ _ => s!"Loaded {state.issues.size} issues"
  | .failure _ error => s!"Request failed: {error.message}"
  | .cancelled _ => "Cancelled"

structure Spec where
  private mk ::
  name : String

namespace Spec

def create (name : String) : Spec := ⟨name⟩

structure Checked where
  private mk ::
  spec : Spec
  initial : State
  decoder : ForeignPort String Page

def check (spec : Spec) : Except Error Checked := do
  if spec.name.isEmpty then throw {
    code := "LRX-EFFECT-002"
    message := "Issue Browser component name must not be empty"
  }
  let decoder ← decoderPort
  pure ⟨spec, IssueBrowser.initial, decoder⟩

end Spec

end LeanRx.IssueBrowser
