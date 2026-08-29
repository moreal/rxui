import LeanRx.Backend.Component
import examples.ToggleLab

/-!
The ADR-0093 witness. The audit is not exercised against hand-written toy
modules: every case below takes the module the component backend really emits
for Toggle Lab and injects one order-breaking statement into one of its real
functions, so a rule that stopped resolving `regions[r][1]` in the emission
would fail here rather than pass vacuously.
-/

namespace LeanRxTest.Backend.RowOrder

open LeanRx LeanRx.Js LeanRxExamples.ToggleLab

private def uint (value : Nat) : Expr := .literal (.number (UInt32.ofNat value))

private def ident (name : String) : IO Ident :=
  match Ident.checked name with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"witness identifier rejected: {error.code}"

/-- The identifiers the injections spell, resolved once through the same
checked constructor the emitter uses. -/
private structure Names where
  regions : Ident
  context : Ident
  aliased : Ident
  key : Ident
  item : Ident
  kept : Ident
  probe : Ident
  rowsParam : Ident
  probeFn : Ident
  probeRows : Ident
  handOff : Ident

private def names : IO Names := do
  pure {
    regions := ← ident "regions"
    context := ← ident "context"
    aliased := ← ident "aliased"
    key := ← ident "key"
    item := ← ident "item"
    kept := ← ident "kept_probe"
    probe := ← ident "probe_row"
    rowsParam := ← ident "rows"
    probeFn := ← ident "$lrx_probe_seek"
    probeRows := ← ident "probe_rows"
    handOff := ← ident "handOff"
  }

private def record (n : Names) (region : Nat) : Expr :=
  .index (.ident n.regions) (uint region)

private def slot (n : Names) (region index : Nat) : Expr :=
  .index (record n region) (uint index)

private def rows (n : Names) (region : Nat) : Expr := slot n region 1

private def call (target : Expr) (method : String) (args : List Expr) : Stmt :=
  .expr <| .call (.index target (.literal (.string method))) (Args.ofList args)

/-- Append statements to one named function of an emitted module. -/
private def inject (module : Module) (target : String) (extra : List Stmt) : Module :=
  { module with declarations := module.declarations.map fun declaration =>
      match declaration with
      | .function value =>
          if value.name.raw == target then
            .function { value with body := value.body ++ extra.toArray }
          else declaration }

/-- Put statements at the head of one named function, which is where ADR-0094
OQ1 injected its `rows["sort"]()` by hand. -/
private def injectFirst (module : Module) (target : String) (extra : List Stmt) : Module :=
  { module with declarations := module.declarations.map fun declaration =>
      match declaration with
      | .function value =>
          if value.name.raw == target then
            .function { value with body := extra.toArray ++ value.body }
          else declaration }

/-- Append a whole function, so the ADR-0095 propagation can be watched
crossing two calls rather than one. -/
private def addFunction (module : Module) (value : Function) : Module :=
  { module with declarations := module.declarations.push (.function value) }

/-- Replace the mount's region record literal, which is the only statement R7
has an opinion about. -/
private def reseat (module : Module) (literal : Expr) : Module :=
  { module with declarations := module.declarations.map fun declaration =>
      match declaration with
      | .function value =>
          if value.name.raw == "mount" then
            .function { value with body := value.body.map fun statement =>
              match statement with
              | .const name _ =>
                  if name.raw == "regions" then .const name literal else statement
              | _ => statement }
          else declaration }

private def dispatch : String := "$lrx_region_0_dispatch"

private def seek : String := "$lrx_row_seek"

private def expectRejected (regionSlot : Nat) (module : Module) (rule label : String) :
    IO Unit :=
  match LeanRx.Backend.RowOrder.audit regionSlot module with
  | .ok _ =>
      throw <| IO.userError s!"row order audit accepted an order-breaking emission: {label}"
  | .error error =>
      unless error.code == "LRX-BE-036" &&
          (error.message.splitOn s!"({rule})").length == 2 do
        throw <| IO.userError
          s!"row order audit rejected {label} under the wrong rule: {error.code} {error.message}"

private def expectAccepted (regionSlot : Nat) (module : Module) (label : String) : IO Unit :=
  match LeanRx.Backend.RowOrder.audit regionSlot module with
  | .ok _ => pure ()
  | .error error =>
      throw <| IO.userError s!"row order audit rejected {label}: {error.code} {error.message}"

private def verify (checked : CheckedComponent ToggleSchema) : IO Unit := do
  let emitted ← match LeanRx.Backend.Component.emit "ToggleLab.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"Toggle emission failed: {error.code} {error.message}"
  let n ← names
  let regionSlot := LeanRx.Backend.Component.regionSlot checked
  let module := emitted.module
  expectAccepted regionSlot module "the emitted Toggle Lab module"

  /- R0: a second name for the region record would put a row table out of the
  audit's reach, so the context's region slot binds to `regions` alone. -/
  expectRejected regionSlot
    (inject module dispatch [.const n.aliased
      (.index (.ident n.context) (uint regionSlot))]) "R0" "a renamed region record"
  expectRejected regionSlot
    (inject module dispatch [.const n.aliased
      (.index (.index (.ident n.context) (uint regionSlot)) (uint 0))])
    "R0" "a doubly indexed context"

  /- R1: the futures ADR-0092 OQ1 named — a table that escapes, a sort, and
  the two insertions a bare method call can spell. -/
  expectRejected regionSlot
    (inject module dispatch [.const n.aliased (rows n 0)]) "R1" "an aliased row table"
  expectRejected regionSlot
    (inject module dispatch [call (rows n 0) "sort" []]) "R1" "a sorted row table"
  expectRejected regionSlot
    (inject module dispatch [call (rows n 0) "unshift" [.array .nil]]) "R1" "a row unshifted"
  expectRejected regionSlot
    (inject module dispatch [call (rows n 0) "reverse" []]) "R1" "a reversed row table"

  /- R2: a row may only enter under its own region's counter. -/
  expectRejected regionSlot
    (inject module dispatch [call (rows n 0) "push"
      [.array (Args.ofList [.ident n.key, .literal .null])]])
    "R2" "a row pushed under the dispatching key"
  expectRejected regionSlot
    (inject module dispatch [call (rows n 0) "push"
      [.array (Args.ofList [uint 0, .literal .null])]])
    "R2" "a row pushed under a constant key"

  /- R3: a splice that inserts, and one that removes a neighbour too. -/
  expectRejected regionSlot
    (inject module dispatch [call (rows n 0) "splice" [uint 0, uint 0, .array .nil]])
    "R3" "a row inserted by splice"
  expectRejected regionSlot
    (inject module dispatch [call (rows n 0) "splice" [uint 0, uint 2]])
    "R3" "two rows spliced at once"

  /- R4: the swap ADR-0092 OQ1 worried about, in each spelling it has. -/
  expectRejected regionSlot
    (inject module dispatch [.assign (.index (rows n 0) (uint 0))
      (.index (rows n 0) (uint 1))]) "R4" "a row replaced in place"
  expectRejected regionSlot
    (inject module dispatch [.assign (.index (.index (rows n 0) (uint 0)) (uint 0)) (uint 7)])
    "R4" "a key slot written through the table"
  expectRejected regionSlot
    (inject module "$lrx_region_0_row" [.assign (.index (.ident n.item) (uint 0)) (uint 7)])
    "R4" "a key slot written through a row parameter"
  expectRejected regionSlot
    (inject module dispatch [.assign (.index (.ident n.regions) (uint 0)) (.array .nil)])
    "R4" "a region record replaced"

  /- R5: a whole-table assignment is the ADR-0050 kept filter and nothing
  else. The accepting case comes first so the rule is not merely a ban. -/
  expectAccepted regionSlot
    (inject module dispatch [
      .const n.kept (.array .nil),
      .forOf n.probe (rows n 0) (Block.ofList [
        call (.ident n.kept) "push" [.ident n.probe]
      ]),
      .assign (.index (record n 0) (uint 1)) (.ident n.kept)])
    "an order-preserving rebuild"
  expectRejected regionSlot
    (inject module dispatch [
      .const n.kept (.array .nil),
      .forOf n.probe (rows n 0) (Block.ofList [
        call (.ident n.kept) "push" [.ident n.probe],
        call (.ident n.kept) "push" [.ident n.probe]
      ]),
      .assign (.index (record n 0) (uint 1)) (.ident n.kept)])
    "R5" "a rebuild that pushes a row twice"
  expectRejected regionSlot
    (inject module dispatch [
      .const n.kept (.array .nil),
      .forOf n.probe (rows n 0) (Block.ofList [
        call (.ident n.kept) "push" [.ident n.probe]
      ]),
      call (.ident n.kept) "reverse" [],
      .assign (.index (record n 0) (uint 1)) (.ident n.kept)])
    "R5" "a rebuild reversed before it is installed"
  expectRejected regionSlot
    (inject module dispatch [.assign (.index (record n 0) (uint 1)) (.array .nil)])
    "R5" "a table replaced by a literal"

  /- R6: the counter never rewinds over a hole. -/
  expectRejected regionSlot
    (inject module dispatch [.assign (.index (record n 0) (uint 2)) (uint 0)])
    "R6" "a rewound key counter"
  expectRejected regionSlot
    (inject module dispatch [.assign (.index (record n 0) (uint 2))
      (.binary .sub (slot n 0 2) (uint 1))]) "R6" "a decremented key counter"
  expectRejected regionSlot
    (inject module dispatch [.assign (.index (record n 0) (uint 2))
      (.binary .add (slot n 0 2) (uint 0))]) "R6" "a counter advanced by zero"

  /- R7: a region mounts empty, so the first key is the smallest. -/
  expectRejected regionSlot
    (reseat module (.array (Args.ofList [.array (Args.ofList [
      .literal .null, .array (Args.ofList [.array .nil]), uint 0,
      .literal (.boolean false), .array .nil])])))
    "R7" "a region mounted with a row already in the table"
  expectRejected regionSlot
    (reseat module (.array (Args.ofList [.array (Args.ofList [
      .literal .null, .array .nil, uint 3,
      .literal (.boolean false), .array .nil])])))
    "R7" "a region mounted with a counter above zero"

  /- ADR-0095. R0's second clause: `$lrx_row_seek` receives `regions[0][1]`
  at seven call sites, so inside the helper the parameter `rows` *is* a row
  table and every rule below bites at it. Each of these was accepted before
  this round — the sort is the one ADR-0094 OQ1 injected by hand and watched
  reach the bundle. -/
  expectRejected regionSlot
    (injectFirst module seek [call (.ident n.rowsParam) "sort" []])
    "R1" "a sorted parameter table"
  expectRejected regionSlot
    (injectFirst module seek [call (.ident n.rowsParam) "reverse" []])
    "R1" "a reversed parameter table"
  expectRejected regionSlot
    (injectFirst module seek [call (.ident n.rowsParam) "unshift" [.array .nil]])
    "R1" "a row unshifted onto a parameter table"
  expectRejected regionSlot
    (injectFirst module seek [.const n.aliased (.ident n.rowsParam)])
    "R1" "an aliased parameter table"
  expectRejected regionSlot
    (injectFirst module seek [.return (.ident n.rowsParam)])
    "R1" "a parameter table returned"
  expectRejected regionSlot
    (injectFirst module seek [.assign (.ident n.rowsParam) (.array .nil)])
    "R4" "a parameter table rebound"

  /- R2 has no counter to name through a parameter, so it is unsatisfiable
  there rather than differently satisfiable — in both spellings a push has. -/
  expectRejected regionSlot
    (injectFirst module seek
      [call (.ident n.rowsParam) "push" [.array (Args.ofList [uint 0, .literal .null])]])
    "R2" "a row pushed onto a parameter table"
  expectRejected regionSlot
    (injectFirst module seek [.forOf n.probe (.ident n.rowsParam) (Block.ofList [
      call (.ident n.rowsParam) "push" [.ident n.probe]])])
    "R2" "a parameter table pushed with one of its own rows"

  /- R3 reads the same at both subjects: a single-row removal is
  order-preserving whichever region the table belongs to, so the rule is a
  shape rule here too and not a ban on touching a parameter. -/
  expectRejected regionSlot
    (injectFirst module seek [call (.ident n.rowsParam) "splice" [uint 0, uint 2]])
    "R3" "two rows spliced out of a parameter table"
  expectRejected regionSlot
    (injectFirst module seek [call (.ident n.rowsParam) "splice" [uint 0, uint 0, .array .nil]])
    "R3" "a row inserted into a parameter table by splice"
  expectAccepted regionSlot
    (injectFirst module seek [call (.ident n.rowsParam) "splice" [uint 0, uint 1]])
    "a single-row removal through a parameter table"

  /- R4 through a parameter table: the swap spelling `paramKeyWrites` could
  never see, because it only ever looked at slot 0 of the parameter itself. -/
  expectRejected regionSlot
    (injectFirst module seek [.assign (.index (.ident n.rowsParam) (uint 1))
      (.index (.ident n.rowsParam) (uint 0))])
    "R4" "a row of a parameter table replaced in place"
  expectRejected regionSlot
    (injectFirst module seek
      [.assign (.index (.index (.ident n.rowsParam) (.ident n.key)) (uint 0)) (uint 7)])
    "R4" "a key slot written through a parameter table"

  /- R5 cannot be spelled through a parameter either: its target is a region
  slot, and a parameter is not one. -/
  expectRejected regionSlot
    (inject module dispatch [.assign (.index (record n 0) (uint 1)) (.ident n.key)])
    "R5" "a table replaced by an ordinary binding"

  /- A callee with no body is not an approved position: the audit follows a
  table into a function this module declares and nowhere else. -/
  expectRejected regionSlot
    (inject module dispatch
      [.expr (.call (.ident n.handOff) (Args.ofList [rows n 0, .literal .null]))])
    "R1" "a row table handed to an imported function"

  /- The propagation is a fixpoint and not one step. `$lrx_probe_seek` never
  sees `regions[0][1]`; it sees what `$lrx_row_seek` forwards, which is two
  calls away from the region record. -/
  let forward : List Stmt :=
    [.expr (.call (.ident n.probeFn) (Args.ofList [.ident n.rowsParam, .ident n.key]))]
  let probe (body : List Stmt) : Function :=
    { name := n.probeFn, params := #[n.probeRows, n.key], body := body.toArray }
  expectAccepted regionSlot
    (addFunction (injectFirst module seek forward)
      (probe [.return (.index (.ident n.probeRows) (.literal (.string "length")))]))
    "a table forwarded to a second helper that reads it"
  expectRejected regionSlot
    (addFunction (injectFirst module seek forward)
      (probe [call (.ident n.probeRows) "sort" []]))
    "R1" "a table forwarded to a second helper that sorts it"
  expectRejected regionSlot
    (addFunction (injectFirst module seek forward)
      (probe [.assign (.index (.index (.ident n.probeRows) (.ident n.key)) (uint 0)) (uint 7)]))
    "R4" "a table forwarded to a second helper that re-keys a row"

  /- …and it is driven by call sites, not by a parameter's name or shape: the
  same helper body is fine while nothing hands it a table. -/
  expectAccepted regionSlot
    (addFunction module (probe [call (.ident n.probeRows) "sort" []]))
    "an uncalled helper sorting its own parameter"

def run : IO Unit :=
  match ToggleLab_spec.check with
  | .error error => throw <| IO.userError s!"Toggle component rejected: {error.code}"
  | .ok checked => verify checked

end LeanRxTest.Backend.RowOrder
