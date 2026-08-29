import LeanRx.Backend.JsAst

/-!
# The row-order audit (ADR-0093)

ADR-0092 resolves a dispatching key to its position by binary search, and the
search is exact only because a region's row table is **strictly ascending in
`row[0]`** at every point a transaction can observe it. ADR-0092 argued that
property site by site — both `push` sites take `regions[r][2]` and then
increment it, no emission assigns a row's key slot again, every removal is
order-preserving, and the backend has no swap, sort or insert-at — and left
its enforcement to review and to a browser gate, naming the gap as its first
open question.

This module closes it. The audit reads the module the component backend just
built and rejects any shape that could break the order, and it is phrased over
the *kinds of thing that can happen to a JavaScript array* rather than over the
sites that happen to exist today: a new emission path inherits the rules
without being enumerated anywhere.

Eight rules, all reported under `LRX-BE-036`:

* **R0** — every row table in the module is spelled `regions[r][1]`. The
  context is never indexed twice, the context's region slot binds only to the
  name `regions`, and the mounted context literal carries exactly that
  binding, so no other spelling can reach a table.
* **R1** — a row table occupies only approved positions: the object of a
  `push`, a `splice` or a `length` read, the iterable of a `for`-of, the object
  of an element read, an argument to one of its own region's handle methods or
  to `$lrx_row_seek`, or the target of a whole-table assignment. An aliasing
  `const`, a `sort`, a `reverse`, an `unshift`, a return, an array element —
  all rejected.
* **R2** — a `push` onto a row table takes one argument, an array literal whose
  head is `regions[r][2]` for the same region. A row therefore cannot enter a
  table with a borrowed, stale or absent key.
* **R3** — a `splice` on a row table takes two arguments and removes exactly
  one row, so it cannot insert.
* **R4** — no row is replaced in place, no key slot is assigned (through a row
  binding, a direct element read, or any function parameter), and no region
  record is replaced wholesale.
* **R5** — a whole-table assignment takes an identifier declared `const k = []`,
  pushed exactly once with the binding of a `for`-of over that same table,
  assigned into that table exactly once, and used nowhere else. That is the
  ADR-0050 kept-filter and nothing else: an order-preserving rebuild.
* **R6** — the key counter is only ever assigned `regions[r][2] + n` for
  `n ≥ 1`, so it never rewinds over a hole.
* **R7** — a mounted region record starts with an empty table and a zero
  counter.

R5 leans on `LRX-BE-018`: because the pushed value must be a `for`-of binding
over the table, the module validator's scoping rule already places the push
inside that loop.

What the audit does *not* see, stated so a future round does not have to
rediscover it: the host. `createKeyedRegion` receives a table by R1's argument
allowance and could in principle reorder it; that side is pinned by
`runtimeAbi` and the region-runtime gate instead.
-/

namespace LeanRx.Backend.RowOrder

open LeanRx.Js

private def contextName : String := "context"
private def regionsName : String := "regions"
private def seekName : String := "$lrx_row_seek"

private def number? : Expr → Option Nat
  | .literal (.number value) => some value.toNat
  | _ => none

/-- `context[slot]`. -/
private def contextRef? : Expr → Option Nat
  | .index (.ident root) index =>
      if root.raw == contextName then number? index else none
  | _ => none

/-- `regions[r]`. -/
private def recordRef? : Expr → Option Nat
  | .index (.ident root) index =>
      if root.raw == regionsName then number? index else none
  | _ => none

/-- `regions[r][slot]`. -/
private def slotRef? : Expr → Option (Nat × Nat)
  | .index record slot =>
      match recordRef? record, number? slot with
      | some region, some index => some (region, index)
      | _, _ => none
  | _ => none

/-- `regions[r][1]`, the row table itself. -/
private def rowTable? (expr : Expr) : Option Nat :=
  match slotRef? expr with
  | some (region, 1) => some region
  | _ => none

/-- `regions[r][2]`, the key counter. -/
private def nextKey? (expr : Expr) : Option Nat :=
  match slotRef? expr with
  | some (region, 2) => some region
  | _ => none

/-- `regions[r][0]`, the keyed region handle the host created. -/
private def handle? (expr : Expr) : Option Nat :=
  match slotRef? expr with
  | some (region, 0) => some region
  | _ => none

private def argList : Args → List Expr
  | .nil => []
  | .cons head tail => head :: argList tail

/-- What one identifier occurrence is doing, so R5 can rule on a rebuild
binding once the whole function has been read. -/
private inductive Use where
  | decl
  | keptPush (region : Nat)
  | tableAssign (region : Nat)
  | other
deriving BEq

private structure Env where
  fn : String
  regionSlot : Nat
  rows : List (Ident × Nat)

/-- Every rejection carries one code; the rule and the offending function are
the message's subject, because the reader who trips this needs to know which
of the eight shapes they emitted, not which line of the audit noticed. -/
private def fail (fn rule detail : String) : Except Error (List (Ident × Use)) :=
  .error {
    code := "LRX-BE-036"
    message := s!"row order audit ({rule}) in '{fn}': {detail}"
  }

/-- The row tuples one statement brings into scope for the statements after
it: an element read bound by `const`, or a `for`-of over the table. -/
private def boundRow? : Stmt → Option (Ident × Nat)
  | .const name (.index target _) => (rowTable? target).map (name, ·)
  | _ => none

/-- Whether an expression denotes a row of some region's table. -/
private def rowRef? (env : Env) : Expr → Option Nat
  | .ident name => env.rows.lookup name
  | .index target _ => rowTable? target
  | _ => none

/-- R2/R3/R1: the shape of a method call on a row table. -/
private def auditRowCall (env : Env) (region : Nat) (name : String) (args : Args) :
    Except Error (List (Ident × Use)) :=
  if name == "push" then
    match argList args with
    | [.array cells] =>
        match argList cells with
        | key :: _ =>
            if nextKey? key == some region then pure []
            else fail env.fn "R2"
              s!"a row pushed onto region {region}'s table does not take regions[{region}][2] as its key"
        | [] => fail env.fn "R2" s!"an empty row is pushed onto region {region}'s table"
    | _ => fail env.fn "R2"
        s!"region {region}'s table takes a push that is not one row literal"
  else if name == "splice" then
    match argList args with
    | [_, count] =>
        if number? count == some 1 then pure []
        else fail env.fn "R3"
          s!"region {region}'s table is spliced by other than exactly one row"
    | _ => fail env.fn "R3"
        s!"region {region}'s table takes a splice that is not a single-row removal"
  else
    fail env.fn "R1" s!"'{name}' is called on region {region}'s row table"

mutual

  /-- Check one expression and collect the identifier census R5 rules on. A
  bare row table or region record is rejected right here, in the `index` case
  that builds one; the positions the rules approve reach their children
  without routing the table itself back through this function. -/
  private def auditExpr (env : Env) : Expr → Except Error (List (Ident × Use))
    | .ident name => pure [(name, .other)]
    | .literal _ => pure []
    | .unary _ value => auditExpr env value
    | .binary _ left right => do
        pure ((← auditExpr env left) ++ (← auditExpr env right))
    | .conditional condition yes no => do
        pure ((← auditExpr env condition) ++ (← auditExpr env yes) ++
          (← auditExpr env no))
    | .array values => auditArgs env values
    /- A rebuild push: `kept["push"](row)` where `row` is a `for`-of binding
    over some region's table. Neither name counts as an ordinary use. -/
    | .call (.index (.ident target) (.literal (.string name)))
        (.cons (.ident value) .nil) =>
        if name == "push" then
          match env.rows.lookup value with
          | some region => pure [(target, .keptPush region)]
          | none => pure [(target, .other), (value, .other)]
        else pure [(target, .other), (value, .other)]
    | .call (.index target (.literal (.string name))) args =>
        match rowTable? target with
        | some region => do
            pure ((← auditRowCall env region name args) ++ (← auditArgs env args))
        | none => do
            let object ← auditExpr env target
            /- R1: a table may be handed to its own region's host handle or to
            the generated key search, and nowhere else. -/
            let carried ←
              if (handle? target).isSome then auditTableArgs env args
              else auditArgs env args
            pure (object ++ carried)
    | .call (.ident name) args =>
        if name.raw == seekName then auditTableArgs env args
        else do pure ((name, .other) :: (← auditArgs env args))
    | .call callee args => do
        pure ((← auditExpr env callee) ++ (← auditArgs env args))
    | .index target index =>
        match rowTable? (.index target index), recordRef? (.index target index) with
        | some region, _ =>
            fail env.fn "R1" s!"region {region}'s row table escapes into a value position"
        | _, some region =>
            fail env.fn "R1" s!"region {region}'s record escapes into a value position"
        | _, _ =>
            if (contextRef? target).isSome then
              fail env.fn "R0" "the region record is reached by indexing the context twice"
            else if (recordRef? target).isSome then
              auditExpr env index
            else
              match rowTable? target, index with
              | some region, .literal (.string name) =>
                  if name == "length" then pure []
                  else fail env.fn "R1"
                    s!"'{name}' is read off region {region}'s row table outside a call"
              | some _, _ => auditExpr env index
              | none, _ => do
                  pure ((← auditExpr env target) ++ (← auditExpr env index))

  private def auditArgs (env : Env) : Args → Except Error (List (Ident × Use))
    | .nil => pure []
    | .cons head tail => do pure ((← auditExpr env head) ++ (← auditArgs env tail))

  /-- Arguments of the two callees a row table may be handed to. -/
  private def auditTableArgs (env : Env) : Args → Except Error (List (Ident × Use))
    | .nil => pure []
    | .cons head tail => do
        let here ← if (rowTable? head).isSome then pure [] else auditExpr env head
        pure (here ++ (← auditTableArgs env tail))

end

/-- R7: a region record is born with an empty table and a zero counter. -/
private def auditRecords (env : Env) : List Expr → Except Error (List (Ident × Use))
  | [] => pure []
  | record :: rest =>
      match record with
      | .array cells =>
          match argList cells with
          | _ :: table :: counter :: _ =>
              match table, number? counter with
              | .array .nil, some 0 => auditRecords env rest
              | _, _ => fail env.fn "R7"
                  "a mounted region record does not start with an empty table and a zero counter"
          | _ => fail env.fn "R7" "a mounted region record is too short to hold a row table"
      | _ => fail env.fn "R7" "a mounted region record is not a literal"

/-- R0's mount half: whatever the context literal carries at the region slot
is the `regions` binding, so every other function's `const regions =
context[s]` is the only way into a row table. -/
private def auditContextLiteral (env : Env) (cells : List Expr) :
    Except Error (List (Ident × Use)) :=
  match cells[env.regionSlot]? with
  | some (.ident carried) =>
      if carried.raw == regionsName then pure []
      else fail env.fn "R0"
        s!"the mounted context carries '{carried.raw}' at its region slot"
  | some _ => fail env.fn "R0"
      "the mounted context carries an expression at its region slot"
  | none => pure []

mutual

  private def auditStmt (env : Env) : Stmt → Except Error (List (Ident × Use))
    /- An empty array is a rebuild candidate until the census says otherwise. -/
    | .const name (.array .nil) => pure [(name, .decl)]
    | .const name value => do
        if contextRef? value == some env.regionSlot && name.raw != regionsName then
          fail env.fn "R0"
            s!"the context's region slot binds to '{name.raw}' rather than '{regionsName}'"
        else
          match value with
          | .array cells =>
              if name.raw == regionsName then auditRecords env (argList cells)
              else do
                let carried ←
                  if name.raw == contextName then auditContextLiteral env (argList cells)
                  else pure []
                pure (carried ++ (← auditExpr env value))
          | _ => auditExpr env value
    | .assign (.ident name) value =>
        if name.raw == regionsName then
          fail env.fn "R4" "the region record array is rebound"
        else do pure ((name, .other) :: (← auditExpr env value))
    | .assign (.index base index) value =>
        match slotRef? (.index base index) with
        | some (region, 1) =>
            match value with
            | .ident name => pure [(name, .tableAssign region)]
            | _ => fail env.fn "R5"
                s!"region {region}'s row table is replaced by an expression that is not a rebuild binding"
        | some (region, 2) =>
            match value with
            | .binary .add left right =>
                match nextKey? left, number? right with
                | some counted, some step =>
                    if counted == region && step ≥ 1 then pure []
                    else fail env.fn "R6"
                      s!"region {region}'s key counter is advanced by another region's counter or by zero"
                | _, _ => fail env.fn "R6"
                    s!"region {region}'s key counter is assigned something other than its own successor"
            | _ => fail env.fn "R6"
                s!"region {region}'s key counter is assigned something other than its own successor"
        | some _ => auditExpr env value
        | none =>
            match rowTable? base, rowRef? env base, number? index with
            | some region, _, _ =>
                fail env.fn "R4" s!"a row of region {region}'s table is replaced in place"
            | none, some region, some 0 =>
                fail env.fn "R4" s!"a row of region {region} has its key slot assigned"
            | _, _, _ =>
                if (recordRef? (.index base index)).isSome then
                  fail env.fn "R4" "a region record is replaced in place"
                else do
                  pure ((← auditExpr env base) ++ (← auditExpr env index) ++
                    (← auditExpr env value))
    | .expr value => auditExpr env value
    | .ifThen condition body => do
        pure ((← auditExpr env condition) ++ (← auditBlock env body))
    | .forOf binding iterable body =>
        match rowTable? iterable with
        | some region =>
            auditBlock { env with rows := (binding, region) :: env.rows } body
        | none => do
            pure ((← auditExpr env iterable) ++ (← auditBlock env body))
    | .whileLoop condition body => do
        pure ((← auditExpr env condition) ++ (← auditBlock env body))
    | .return value => auditExpr env value

  private def auditBlock (env : Env) : Block → Except Error (List (Ident × Use))
    | .nil => pure []
    | .cons head tail => do
        let here ← auditStmt env head
        let next := match boundRow? head with
          | some binding => { env with rows := binding :: env.rows }
          | none => env
        pure (here ++ (← auditBlock next tail))

end

/-- R5's verdict: a rebuild binding is declared empty once, filled once from a
`for`-of over the very table it replaces, installed once, and never touched
otherwise. -/
private def rebuilt (uses : List (Ident × Use)) (name : Ident) (region : Nat) : Bool :=
  let mine := uses.filterMap fun entry =>
    if entry.1 == name then some entry.2 else none
  mine.length == 3 && mine.count Use.decl == 1 &&
    mine.count (Use.keptPush region) == 1 &&
    mine.count (Use.tableAssign region) == 1

/-- R4's parameter half: no function writes any parameter's slot 0, so a row
that reached a function as an argument cannot have its key rewritten there
either. -/
private def paramKeyWrites (params : List Ident) : Block → Bool
  | .nil => false
  | .cons head tail =>
      let here := match head with
        | .assign (.index (.ident name) index) _ =>
            params.contains name && number? index == some 0
        | .ifThen _ body => paramKeyWrites params body
        | .forOf _ _ body => paramKeyWrites params body
        | .whileLoop _ body => paramKeyWrites params body
        | _ => false
      here || paramKeyWrites params tail

private def auditFunction (regionSlot : Nat) (value : Function) : Except Error Unit := do
  let env : Env := { fn := value.name.raw, regionSlot, rows := [] }
  let body := Block.ofList value.body.toList
  if paramKeyWrites value.params.toList body then
    throw {
      code := "LRX-BE-036"
      message := s!"row order audit (R4) in '{value.name.raw}': a parameter's key slot is assigned"
    }
  let uses ← auditBlock env body
  for entry in uses do
    if let .tableAssign region := entry.2 then
      unless rebuilt uses entry.1 region do
        throw {
          code := "LRX-BE-036"
          message :=
            s!"row order audit (R5) in '{value.name.raw}': '{entry.1.raw}' replaces region {region}'s row table without being an order-preserving rebuild"
        }

/-- The ADR-0093 audit over one emitted component module. `regionSlot` is the
context slot the component's region record occupies, which is what makes R0's
claim — every row table is spelled `regions[r][1]` — checkable. -/
def audit (regionSlot : Nat) (module : Module) : Except Error Unit := do
  for declaration in module.declarations do
    match declaration with
    | .function value => auditFunction regionSlot value

end LeanRx.Backend.RowOrder
