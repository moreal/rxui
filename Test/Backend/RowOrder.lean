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

private def names : IO Names := do
  pure {
    regions := ← ident "regions"
    context := ← ident "context"
    aliased := ← ident "aliased"
    key := ← ident "key"
    item := ← ident "item"
    kept := ← ident "kept_probe"
    probe := ← ident "probe_row"
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
    | .error error => throw <| IO.userError s!"Toggle emission failed: {error.code}"
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

def run : IO Unit :=
  match ToggleLab_spec.check with
  | .error error => throw <| IO.userError s!"Toggle component rejected: {error.code}"
  | .ok checked => verify checked

end LeanRxTest.Backend.RowOrder
