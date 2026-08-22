import LeanRx.Backend.FormDom
import LeanRx.Backend.Manifest
import LeanRx.IssueBrowser.Model

namespace LeanRx.Backend.IssueBrowser

open LeanRx.Js

structure Emitted where
  private mk ::
  module : Module
  manifest : ComponentManifest
deriving Repr, BEq

private structure RuntimeNames where
  createElement : Ident
  createText : Ident
  setAttribute : Ident
  append : Ident
  childAt : Ident
  setText : Ident
  setProperty : Ident
  listen : Ident
  listenValue : Ident
  makeDisposer : Ident
  createKeyedRegion : Ident
  createEffectRuntime : Ident
  makeEffectDisposer : Ident
  decodeIssueResponse : Ident
  string : Ident

private def runtimeNames : Except Js.Error RuntimeNames := do
  pure {
    createElement := ← Ident.checked "createElement"
    createText := ← Ident.checked "createText"
    setAttribute := ← Ident.checked "setAttribute"
    append := ← Ident.checked "append"
    childAt := ← Ident.checked "childAt"
    setText := ← Ident.checked "setText"
    setProperty := ← Ident.checked "setProperty"
    listen := ← Ident.checked "listen"
    listenValue := ← Ident.checked "listenValue"
    makeDisposer := ← Ident.checked "makeDisposer"
    createKeyedRegion := ← Ident.checked "createKeyedRegion"
    createEffectRuntime := ← Ident.checked "createEffectRuntime"
    makeEffectDisposer := ← Ident.checked "makeEffectDisposer"
    decodeIssueResponse := ← Ident.checked "decodeIssueResponse"
    string := ← Ident.checked "String"
  }

private def uint (value : Nat) : Expr := .literal (.number (UInt32.ofNat value))
private def bigint (value : Nat) : Expr := .literal (.bigint (Int.ofNat value))
private def negativeOne : Expr := .unary .neg (uint 1)
private def indexAt (target : Expr) (index : Nat) : Expr := .index target (uint index)
private def arrayAt (name : Ident) (index : Nat) : Expr := indexAt (.ident name) index
private def stateAt (state : Ident) (index : Nat) : Expr := arrayAt state index
private def contextAt (context : Ident) (index : Nat) : Expr := arrayAt context index
private def property (target : Expr) (name : String) : Expr :=
  .index target (.literal (.string name))
private def call (name : Ident) (args : List Expr) : Expr :=
  .call (.ident name) (.ofList args)
private def callExpr (callee : Expr) (args : List Expr) : Expr := .call callee (.ofList args)
private def method (target : Expr) (name : String) (args : List Expr) : Expr :=
  callExpr (property target name) args
private def equals (left right : Expr) : Expr := .binary .eq left right
private def both (left right : Expr) : Expr := .binary .and left right

private def incrementAt (array : Ident) (index : Nat) : Stmt :=
  .assign (.index (.ident array) (uint index))
    (.binary .add (arrayAt array index) (uint 1))

private def assignState (state metrics : Ident) (index : Nat) (value : Expr) : List Stmt := [
  .assign (.index (.ident state) (uint index)) value,
  incrementAt metrics 2
]

private def trace (metrics : Ident) (message : String) : Stmt :=
  .expr <| method (arrayAt metrics 7) "push" [.literal (.string message)]

private def mountIssueFunction (runtime : RuntimeNames) : Except Js.Error Function := do
  let item ← Ident.checked "item"
  let index ← Ident.checked "index"
  let row ← Ident.checked "issueRow"
  let text ← Ident.checked "issueText"
  let metrics ← Ident.checked "metrics"
  pure {
    name := ← Ident.checked "$lrx_mountIssue"
    params := #[item, index]
    body := #[
      .const metrics (indexAt (.ident item) 2),
      .const row (call runtime.createElement [.literal (.string "li")]),
      .expr <| call runtime.setAttribute [
        .ident row, .literal (.string "data-issue-id"),
        call runtime.string [indexAt (.ident item) 0]],
      incrementAt metrics 6,
      .const text (call runtime.createText [indexAt (.ident item) 1]),
      .expr <| call runtime.append [.ident row, .ident text],
      .return (.ident row)
    ]
  }

private def updateIssueFunction (runtime : RuntimeNames) : Except Js.Error Function := do
  let row ← Ident.checked "issueRow"
  let item ← Ident.checked "item"
  let index ← Ident.checked "index"
  let metrics ← Ident.checked "metrics"
  pure {
    name := ← Ident.checked "$lrx_updateIssue"
    params := #[row, item, index]
    body := #[
      .const metrics (indexAt (.ident item) 2),
      .expr <| call runtime.setText [
        call runtime.childAt [.ident row, uint 0], indexAt (.ident item) 1],
      incrementAt metrics 6,
      .return (.literal .null)
    ]
  }

private def disposeIssueFunction : Except Js.Error Function := do
  pure {
    name := ← Ident.checked "$lrx_disposeIssue"
    params := #[← Ident.checked "issueRow", ← Ident.checked "key"]
    body := #[.return (.literal .null)]
  }

private def uniqueIssuesFunction : Except Js.Error Function := do
  let issues ← Ident.checked "issues"
  let seen ← Ident.checked "seenIds"
  let issue ← Ident.checked "candidateIssue"
  let key ← Ident.checked "candidateKey"
  pure {
    name := ← Ident.checked "$lrx_uniqueIssues"
    params := #[issues]
    body := #[
      .const seen (.array .nil),
      .forOf issue (.ident issues) <| .ofList [
        .const key (indexAt (.ident issue) 0),
        .ifThen (method (.ident seen) "includes" [.ident key]) <|
          .ofList [.return (.literal (.boolean false))],
        .expr <| method (.ident seen) "push" [.ident key]
      ],
      .return (.literal (.boolean true))
    ]
  }

private def renderFunction (runtime : RuntimeNames) : Except Js.Error Function := do
  let name ← Ident.checked "$lrx_renderIssues"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let region ← Ident.checked "issueRegion"
  let metrics ← Ident.checked "metrics"
  let item ← Ident.checked "issue"
  let items ← Ident.checked "regionItems"
  let status ← Ident.checked "statusValue"
  let count ← Ident.checked "issueCount"
  let code ← Ident.checked "resourceCode"
  let fallback := .conditional (equals (.ident code) (uint 1))
      (.literal (.string "Loading")) <|
    .conditional (equals (.ident code) (uint 2))
      (.binary .add (.literal (.string "Loaded "))
        (.binary .add (.ident count) (.literal (.string " issues")))) <|
    .conditional (equals (.ident code) (uint 3))
      (.binary .add (.literal (.string "Request failed: ")) (stateAt state 12)) <|
    .conditional (equals (.ident code) (uint 4))
      (.literal (.string "Cancelled")) (.literal (.string "Idle"))
  pure {
    name
    params := #[state, context]
    body := #[
      .const region (contextAt context 4),
      .const metrics (contextAt context 6),
      .const items (.array .nil),
      .forOf item (stateAt state 1) <| .ofList [
        .expr <| method (.ident items) "push" [
          .array <| .ofList [indexAt (.ident item) 0, indexAt (.ident item) 1,
            .ident metrics]]
      ],
      .expr <| method (.ident region) "update" [.ident items],
      .const code (stateAt state 4),
      .const count (call runtime.string [property (stateAt state 1) "length"]),
      .const status fallback,
      .expr <| call runtime.setText [contextAt context 1, .ident status],
      .expr <| call runtime.setProperty [
        contextAt context 2, .literal (.string "disabled"),
        .binary .or (.unary .not <| stateAt state 3) (equals (.ident code) (uint 1))],
      .expr <| call runtime.setProperty [
        contextAt context 3, .literal (.string "disabled"),
        .unary .not <| equals (.ident code) (uint 3)],
      incrementAt metrics 5,
      incrementAt metrics 5,
      incrementAt metrics 5,
      incrementAt metrics 6,
      incrementAt metrics 6,
      incrementAt metrics 6,
      trace metrics "issue:render",
      .return (.literal .null)
    ]
  }

private def beginFunction (runtime : RuntimeNames) (render received : Ident) :
    Except Js.Error Function := do
  let name ← Ident.checked "$lrx_beginIssueRequest"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let query ← Ident.checked "query"
  let page ← Ident.checked "page"
  let metrics ← Ident.checked "metrics"
  let effects ← Ident.checked "effects"
  let handle ← Ident.checked "requestHandle"
  let hadActive ← Ident.checked "hadActiveRequest"
  let previousHandle ← Ident.checked "previousHandle"
  let body : List Stmt := [
    .const metrics (contextAt context 6),
    .const effects (contextAt context 5),
    .ifThen (stateAt state 11) <| .ofList [.return (.literal .null)],
    .const hadActive (equals (stateAt state 4) (uint 1)),
    .const previousHandle (stateAt state 5),
    .const handle (stateAt state 10)
  ] ++ assignState state metrics 0 (.ident query) ++
    assignState state metrics 4 (uint 1) ++
    assignState state metrics 5 (.ident handle) ++
    assignState state metrics 6 (.ident query) ++
    assignState state metrics 7 (.ident page) ++
    assignState state metrics 8 (.ident query) ++
    assignState state metrics 9 (.ident page) ++
    assignState state metrics 10 (.binary .add (.ident handle) (uint 1)) ++
    assignState state metrics 12 (.literal (.string "")) ++ [
    incrementAt metrics 1,
    trace metrics "command:http:start",
    .expr <| call render [.ident state, .ident context],
    .ifThen (.ident hadActive) <| .ofList [
      .expr <| method (.ident effects) "cancel" [.ident previousHandle],
      trace metrics "command:http:cancel"
    ],
    .expr <| method (.ident effects) "http" [
      .ident handle, .literal (.string "GET"), .literal (.string "/api/issues"),
      .array <| .ofList [
        .array <| .ofList [.literal (.string "q"), .ident query],
        .array <| .ofList [.literal (.string "page"), call runtime.string [.ident page]]
      ],
      .ident runtime.decodeIssueResponse, .ident state, .ident context, .ident received],
    .return (.literal .null)
  ]
  pure { name, params := #[state, context, query, page], body := body.toArray }

private def receivedFunction (render uniqueIssues : Ident) : Except Js.Error Function := do
  let name ← Ident.checked "$lrx_issueReceived"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let handle ← Ident.checked "handle"
  let result ← Ident.checked "result"
  let metrics ← Ident.checked "metrics"
  let page ← Ident.checked "decodedPage"
  let nextIssues ← Ident.checked "nextIssues"
  let condition := both (equals (stateAt state 4) (uint 1))
    (equals (stateAt state 5) (.ident handle))
  pure {
    name
    params := #[state, context, handle, result]
    body := #[
      .const metrics (contextAt context 6),
      .ifThen condition <| .ofList <| [
        .ifThen (property (.ident result) "ok") <| .ofList <| [
          .const page (property (.ident result) "value"),
          .const nextIssues (.conditional (equals (stateAt state 7) (bigint 1))
            (indexAt (.ident page) 0)
            (method (stateAt state 1) "concat" [indexAt (.ident page) 0]))
        ] ++ [
          .ifThen (call uniqueIssues [.ident nextIssues]) <| .ofList <|
            assignState state metrics 1 (.ident nextIssues) ++
            assignState state metrics 2 (stateAt state 7) ++
            assignState state metrics 3 (indexAt (.ident page) 1) ++
            assignState state metrics 4 (uint 2) ++
            assignState state metrics 5 negativeOne ++
            assignState state metrics 12 (.literal (.string "")) ++ [
            trace metrics "command:http:succeeded"
          ],
          .ifThen (.unary .not <| call uniqueIssues [.ident nextIssues]) <| .ofList <|
            assignState state metrics 4 (uint 3) ++
            assignState state metrics 5 negativeOne ++
            assignState state metrics 12
              (.literal (.string "issue response contains duplicate IDs")) ++ [
            trace metrics "command:http:failed"
          ]
        ],
        .ifThen (.unary .not <| property (.ident result) "ok") <| .ofList <|
          assignState state metrics 4 (uint 3) ++
          assignState state metrics 5 negativeOne ++
          assignState state metrics 12
            (property (property (.ident result) "error") "message") ++ [
          trace metrics "command:http:failed"
        ],
        incrementAt metrics 1,
        .expr <| call render [.ident state, .ident context]
      ],
      .return (.literal .null)
    ]
  }

private def queryFunction (begin : Ident) : Except Js.Error Function := do
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let value ← Ident.checked "value"
  pure {
    name := ← Ident.checked "$lrx_issueQuery"
    params := #[state, context, value]
    body := #[
      .expr <| call begin [.ident state, .ident context, .ident value, bigint 1],
      .return (.literal .null)
    ]
  }

private def searchFunction (begin : Ident) : Except Js.Error Function := do
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  pure {
    name := ← Ident.checked "$lrx_issueSearch"
    params := #[state, context]
    body := #[
      .expr <| call begin [.ident state, .ident context, stateAt state 0, bigint 1],
      .return (.literal .null)
    ]
  }

private def nextFunction (begin : Ident) : Except Js.Error Function := do
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  pure {
    name := ← Ident.checked "$lrx_issueNext"
    params := #[state, context]
    body := #[
      .ifThen (stateAt state 3) <| .ofList [
        .expr <| call begin [.ident state, .ident context, stateAt state 0,
          .binary .add (stateAt state 2) (bigint 1)]
      ],
      .return (.literal .null)
    ]
  }

private def retryFunction (begin : Ident) : Except Js.Error Function := do
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  pure {
    name := ← Ident.checked "$lrx_issueRetry"
    params := #[state, context]
    body := #[
      .expr <| call begin [.ident state, .ident context, stateAt state 8, stateAt state 9],
      .return (.literal .null)
    ]
  }

private def button (runtime : RuntimeNames) (name label : Ident) (text : String) : List Stmt := [
  .const name (call runtime.createElement [.literal (.string "button")]),
  .expr <| call runtime.setAttribute [
    .ident name, .literal (.string "type"), .literal (.string "button")],
  .const label (call runtime.createText [.literal (.string text)]),
  .expr <| call runtime.append [.ident name, .ident label]
]

private def mountFunction (runtime : RuntimeNames) (componentName : String)
    (mountIssue updateIssue disposeIssue begin query search next retry : Ident) :
    Except Js.Error Function := do
  let name ← Ident.checked "mount"
  let target ← Ident.checked "target"
  let adapters ← Ident.checked "adapters"
  let root ← Ident.checked "root"
  let heading ← Ident.checked "heading"
  let headingText ← Ident.checked "headingText"
  let input ← Ident.checked "queryInput"
  let searchButton ← Ident.checked "searchButton"
  let searchText ← Ident.checked "searchText"
  let nextButton ← Ident.checked "nextButton"
  let nextText ← Ident.checked "nextText"
  let retryButton ← Ident.checked "retryButton"
  let retryText ← Ident.checked "retryText"
  let status ← Ident.checked "status"
  let statusText ← Ident.checked "statusText"
  let list ← Ident.checked "issueList"
  let metrics ← Ident.checked "metrics"
  let state ← Ident.checked "state"
  let region ← Ident.checked "region"
  let effects ← Ident.checked "effects"
  let context ← Ident.checked "context"
  let offInput ← Ident.checked "offInput"
  let offSearch ← Ident.checked "offSearch"
  let offNext ← Ident.checked "offNext"
  let offRetry ← Ident.checked "offRetry"
  let baseDisposer ← Ident.checked "baseDisposer"
  let disposer ← Ident.checked "disposer"
  let body : List Stmt := [
    .const root (call runtime.createElement [.literal (.string "main")]),
    .expr <| call runtime.setAttribute [
      .ident root, .literal (.string "class"), .literal (.string "leanrx-issues")],
    .const heading (call runtime.createElement [.literal (.string "h1")]),
    .const headingText (call runtime.createText [.literal (.string componentName)]),
    .expr <| call runtime.append [.ident heading, .ident headingText],
    .expr <| call runtime.append [.ident root, .ident heading],
    .const input (call runtime.createElement [.literal (.string "input")]),
    .expr <| call runtime.setAttribute [
      .ident input, .literal (.string "aria-label"), .literal (.string "Issue query")],
    .expr <| call runtime.setProperty [
      .ident input, .literal (.string "value"), .literal (.string "lean")],
    .expr <| call runtime.append [.ident root, .ident input]
  ] ++ button runtime searchButton searchText "Search" ++ [
    .expr <| call runtime.append [.ident root, .ident searchButton]
  ] ++ button runtime nextButton nextText "Next page" ++ [
    .expr <| call runtime.append [.ident root, .ident nextButton]
  ] ++ button runtime retryButton retryText "Retry" ++ [
    .expr <| call runtime.append [.ident root, .ident retryButton],
    .const status (call runtime.createElement [.literal (.string "p")]),
    .expr <| call runtime.setAttribute [
      .ident status, .literal (.string "role"), .literal (.string "status")],
    .expr <| call runtime.setAttribute [
      .ident status, .literal (.string "aria-live"), .literal (.string "polite")],
    .const statusText (call runtime.createText [.literal (.string "Idle")]),
    .expr <| call runtime.append [.ident status, .ident statusText],
    .expr <| call runtime.append [.ident root, .ident status],
    .const list (call runtime.createElement [.literal (.string "ul")]),
    .expr <| call runtime.setAttribute [
      .ident list, .literal (.string "aria-label"), .literal (.string "Issues")],
    .expr <| call runtime.append [.ident root, .ident list],
    .const metrics (.array <| .ofList [
      uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, .array .nil,
      uint 0, uint 0]),
    .const state (.array <| .ofList [
      .literal (.string "lean"), .array .nil, bigint 0, .literal (.boolean false),
      uint 0, negativeOne, .literal (.string ""), bigint 0,
      .literal (.string "lean"), bigint 1, uint 0, .literal (.boolean false),
      .literal (.string "")]),
    .const region (call runtime.createKeyedRegion [
      .ident list, .ident mountIssue, .ident updateIssue, .ident disposeIssue]),
    .const effects (call runtime.createEffectRuntime [.ident metrics, .ident adapters]),
    .const context (.array <| .ofList [
      .ident region, .ident statusText, .ident nextButton, .ident retryButton,
      .ident region, .ident effects, .ident metrics]),
    .expr <| call runtime.append [.ident target, .ident root],
    .const offInput (call runtime.listenValue [
      .ident input, .literal (.string "input"), .ident state, .ident context, .ident query]),
    .const offSearch (call runtime.listen [
      .ident searchButton, .literal (.string "click"), .ident state, .ident context,
      .ident search]),
    .const offNext (call runtime.listen [
      .ident nextButton, .literal (.string "click"), .ident state, .ident context,
      .ident next]),
    .const offRetry (call runtime.listen [
      .ident retryButton, .literal (.string "click"), .ident state, .ident context,
      .ident retry]),
    .const baseDisposer (call runtime.makeDisposer [
      .ident root, .array <| .ofList [
        .ident offInput, .ident offSearch, .ident offNext, .ident offRetry,
        property (.ident region) "dispose"],
      .ident metrics, .array <| .ofList [.ident region]]),
    .const disposer (call runtime.makeEffectDisposer [
      .ident baseDisposer, .ident state, uint 11, .ident effects]),
    .expr <| call begin [
      .ident state, .ident context, .literal (.string "lean"), bigint 1],
    .return (.ident disposer)
  ]
  pure { name, params := #[target, adapters], body := body.toArray }

def emit (moduleName : String) (checked : LeanRx.IssueBrowser.Spec.Checked) :
    Except Js.Error Emitted := do
  let runtime ← runtimeNames
  let mountIssue ← mountIssueFunction runtime
  let updateIssue ← updateIssueFunction runtime
  let disposeIssue ← disposeIssueFunction
  let uniqueIssues ← uniqueIssuesFunction
  let render ← renderFunction runtime
  let receivedName ← Ident.checked "$lrx_issueReceived"
  let begin ← beginFunction runtime render.name receivedName
  let received ← receivedFunction render.name uniqueIssues.name
  let query ← queryFunction begin.name
  let search ← searchFunction begin.name
  let next ← nextFunction begin.name
  let retry ← retryFunction begin.name
  let mount ← mountFunction runtime checked.spec.name mountIssue.name updateIssue.name
    disposeIssue.name begin.name query.name search.name next.name retry.name
  let module : Module := {
    globals := #[runtime.string]
    imports := #[
      { source := "./leanrx_dom.mjs", names := #[
          (runtime.createElement, runtime.createElement),
          (runtime.createText, runtime.createText),
          (runtime.setAttribute, runtime.setAttribute),
          (runtime.append, runtime.append),
          (runtime.childAt, runtime.childAt),
          (runtime.setText, runtime.setText),
          (runtime.setProperty, runtime.setProperty),
          (runtime.listen, runtime.listen)
        ] },
      { source := "./leanrx_form_events.mjs", names := #[
          (runtime.listenValue, runtime.listenValue)
        ] },
      { source := "./leanrx_host.mjs", names := #[
          (runtime.makeDisposer, runtime.makeDisposer)
        ] },
      { source := "./leanrx_region.mjs", names := #[
          (runtime.createKeyedRegion, runtime.createKeyedRegion)
        ] },
      { source := "./leanrx_effects.mjs", names := #[
          (runtime.createEffectRuntime, runtime.createEffectRuntime),
          (runtime.makeEffectDisposer, runtime.makeEffectDisposer)
        ] },
      { source := "./leanrx_issue_ports.mjs", names := #[
          (runtime.decodeIssueResponse, runtime.decodeIssueResponse)
        ] }
    ]
    declarations := #[
      .function mountIssue, .function updateIssue, .function disposeIssue,
      .function uniqueIssues,
      .function render, .function begin, .function received, .function query,
      .function search, .function next, .function retry, .function mount]
    exports := #[{ localName := mount.name, exportName := mount.name }]
  }
  module.validate
  pure ⟨module, {
    compilerVersion := LeanRx.version
    leanToolchain := LeanRx.leanToolchain
    moduleName
    graphHash := "issues:query->resource->keyed-list"
    runtimeAbi := LeanRx.runtimeAbi
    exports := #["mount"]
    stateSlots := #[.string, .list (.record "Issue"), .nat, .bool]
    sourceCount := 4
    derivedCount := 0
    textSinkCount := 1
    eventCount := 4
    hostImports := #["./leanrx_dom.mjs", "./leanrx_form_events.mjs", "./leanrx_host.mjs",
      "./leanrx_region.mjs", "./leanrx_effects.mjs", "./leanrx_issue_ports.mjs"]
    ports := #[PortManifest.ofForeign checked.decoder]
    features := #["commands", "http", "resource", "pagination", "keyed",
      "owned-cancellation", "foreign:decodeIssueResponse", "instrumentation"]
  }⟩

end LeanRx.Backend.IssueBrowser
