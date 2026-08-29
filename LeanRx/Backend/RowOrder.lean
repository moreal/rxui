import LeanRx.Backend.JsAst

/-!
# The row-order audit (ADR-0093, ADR-0095)

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

* **R0** — every row table in the module is *named*. Two spellings and no
  others: `regions[r][1]`, where the context is never indexed twice, the
  context's region slot binds only to the name `regions`, and the mounted
  context literal carries exactly that binding; and, since ADR-0095, a
  **parameter of a module function that some call site hands one to**. The
  second set is the fixpoint of "argument `i` of `f` receives a row table",
  computed before any rule is applied, so a table cannot reach code the audit
  is not already looking at.
* **R1** — a row table occupies only approved positions: the object of a
  `push`, a `splice` or a `length` read, the iterable of a `for`-of, the object
  of an element read, an argument to one of its own region's handle methods or
  to a function this module declares, or the target of a whole-table
  assignment. An aliasing `const`, a `sort`, a `reverse`, an `unshift`, a
  return, an array element, an argument to an imported function — all rejected.
* **R2** — a `push` onto a row table takes one argument, an array literal whose
  head is `regions[r][2]` for the same region. A row therefore cannot enter a
  table with a borrowed, stale or absent key. A table reached through a
  parameter has no region and so no counter in scope: R2 is unsatisfiable
  there, which is to say a parameter table cannot be pushed onto at all.
* **R3** — a `splice` on a row table takes two arguments and removes exactly
  one row, so it cannot insert. This one rule reads the same at both subjects:
  a single-row removal is order-preserving whichever region the table is.
* **R4** — no row is replaced in place, no key slot is assigned (through a row
  binding, a direct element read, or any function parameter), no region record
  is replaced wholesale, and no row table parameter is rebound.
* **R5** — a whole-table assignment takes an identifier declared `const k = []`,
  pushed exactly once with the binding of a `for`-of over that same table,
  assigned into that table exactly once, and used nowhere else. That is the
  ADR-0050 kept-filter and nothing else: an order-preserving rebuild. Its
  target is a region slot, so it too is unsatisfiable through a parameter.
* **R6** — the key counter is only ever assigned `regions[r][2] + n` for
  `n ≥ 1`, so it never rewinds over a hole.
* **R7** — a mounted region record starts with an empty table and a zero
  counter.

R5 leans on `LRX-BE-018`: because the pushed value must be a `for`-of binding
over the table, the module validator's scoping rule already places the push
inside that loop.

What the audit does *not* see, stated so a future round does not have to
rediscover it: the host. `createKeyedRegion` receives a table by R1's argument
allowance and could in principle reorder it; that side is pinned by the
ADR-0094 caller-array contract at `check_region_runtime.sh` instead.
-/

namespace LeanRx.Backend.RowOrder

open LeanRx.Js

private def contextName : String := "context"
private def regionsName : String := "regions"

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

/-- `regions[r][1]`, a row table under its own region's spelling. -/
private def regionTable? (expr : Expr) : Option Nat :=
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

/-! ## R0's second clause: which parameters carry a row table (ADR-0095)

A row table crosses into a function by being an argument, and inside that
function it is no longer spelled `regions[r][1]` — it is a parameter name. The
audit therefore computes, before it applies any rule, the set of
`(function, argument position)` pairs that ever receive one, and treats the
matching parameters as row tables. The set is a least fixpoint: a table handed
on from one helper to the next taints the next helper's parameter too. -/

/-- One call-site obligation: argument `index` of `fn` receives a row table
somewhere in this module, so `fn`'s parameter at that position is a row table
wherever the rules are applied to `fn`'s body. -/
private structure Site where
  fn : Ident
  index : Nat
deriving BEq

/-- Whether an expression denotes a row table, given the parameters of the
function it appears in that already carry one. -/
private def tableExpr (tables : List Ident) : Expr → Bool
  | .ident name => tables.contains name
  | expr => (regionTable? expr).isSome

/-- The obligations one argument list raises. Only a function this module
declares is followed: an imported callee has no body to audit, so handing it a
table is R1's business rather than a site. -/
private def argSites (tables locals : List Ident) (callee : Ident) :
    Nat → Args → List Site
  | _, .nil => []
  | index, .cons head tail =>
      let here :=
        if locals.contains callee && tableExpr tables head then
          [{ fn := callee, index : Site }]
        else []
      here ++ argSites tables locals callee (index + 1) tail

mutual

  private def siteExpr (tables locals : List Ident) : Expr → List Site
    | .ident _ => []
    | .literal _ => []
    | .unary _ value => siteExpr tables locals value
    | .binary _ left right =>
        siteExpr tables locals left ++ siteExpr tables locals right
    | .conditional condition yes no =>
        siteExpr tables locals condition ++ siteExpr tables locals yes ++
          siteExpr tables locals no
    | .array values => siteArgs tables locals values
    | .call (.ident callee) args =>
        argSites tables locals callee 0 args ++ siteArgs tables locals args
    | .call callee args =>
        siteExpr tables locals callee ++ siteArgs tables locals args
    | .index target index =>
        siteExpr tables locals target ++ siteExpr tables locals index

  private def siteArgs (tables locals : List Ident) : Args → List Site
    | .nil => []
    | .cons head tail =>
        siteExpr tables locals head ++ siteArgs tables locals tail

end

mutual

  private def siteStmt (tables locals : List Ident) : Stmt → List Site
    | .const _ value => siteExpr tables locals value
    | .assign (.ident _) value => siteExpr tables locals value
    | .assign (.index target index) value =>
        siteExpr tables locals target ++ siteExpr tables locals index ++
          siteExpr tables locals value
    | .expr value => siteExpr tables locals value
    | .ifThen condition body =>
        siteExpr tables locals condition ++ siteBlock tables locals body
    | .forOf _ iterable body =>
        siteExpr tables locals iterable ++ siteBlock tables locals body
    | .whileLoop condition body =>
        siteExpr tables locals condition ++ siteBlock tables locals body
    | .return value => siteExpr tables locals value

  private def siteBlock (tables locals : List Ident) : Block → List Site
    | .nil => []
    | .cons head tail =>
        siteStmt tables locals head ++ siteBlock tables locals tail

end

/-- The parameters of one function that the obligations so far make row
tables. -/
private def tableParams (sites : List Site) (fn : Ident) :
    Nat → List Ident → List Ident
  | _, [] => []
  | index, name :: rest =>
      (if sites.contains { fn, index } then [name] else []) ++
        tableParams sites fn (index + 1) rest

private def merge : List Site → List Site → List Site
  | seen, [] => seen
  | seen, site :: rest =>
      merge (if seen.contains site then seen else seen ++ [site]) rest

/-- One pass over every function, reading each with the obligations known so
far and adding the ones its body raises. -/
private def sweep (locals : List Ident) (functions : List Function)
    (sites : List Site) : List Site :=
  functions.foldl (fun seen value =>
    let tables := tableParams seen value.name 0 value.params.toList
    merge seen (siteBlock tables locals (Block.ofList value.body.toList))) sites

/-- The fixpoint. Every pass that changes anything adds at least one pair and
the pairs are bounded by the module's total parameter count, so that count is a
sufficient budget; `audit` re-checks stability rather than trusting the
arithmetic. -/
private def propagate (locals : List Ident) (functions : List Function) :
    Nat → List Site → List Site
  | 0, sites => sites
  | fuel + 1, sites =>
      let next := sweep locals functions sites
      if next.length == sites.length then sites
      else propagate locals functions fuel next

/-! ## The rules -/

/-- A row table under one of R0's two spellings. Every rule below is stated
over this, not over `regions[r][1]`, which is what makes a helper's parameter
carry the same obligations as the table the caller passed. -/
private inductive Table where
  | region (index : Nat)
  | param (name : Ident)
deriving BEq

private def Table.describe : Table → String
  | .region index => s!"region {index}'s row table"
  | .param name => s!"the row table parameter '{name.raw}'"

/-- What one identifier occurrence is doing, so R5 can rule on a rebuild
binding once the whole function has been read. -/
private inductive Use where
  | decl
  | keptPush (table : Table)
  | tableAssign (region : Nat)
  | other
deriving BEq

private structure Env where
  fn : String
  regionSlot : Nat
  rows : List (Ident × Table)
  tables : List Ident
  locals : List Ident

/-- R0: the two spellings of a row table, and nothing else. -/
private def tableOf? (env : Env) : Expr → Option Table
  | .ident name => if env.tables.contains name then some (.param name) else none
  | expr => (regionTable? expr).map Table.region

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
private def boundRow? (env : Env) : Stmt → Option (Ident × Table)
  | .const name (.index target _) => (tableOf? env target).map (name, ·)
  | _ => none

/-- Whether an expression denotes a row of some table. -/
private def rowRef? (env : Env) : Expr → Option Table
  | .ident name => env.rows.lookup name
  | .index target _ => tableOf? env target
  | _ => none

/-- R2/R3/R1: the shape of a method call on a row table. -/
private def auditRowCall (env : Env) (table : Table) (name : String) (args : Args) :
    Except Error (List (Ident × Use)) :=
  if name == "push" then
    match table with
    | .param _ =>
        fail env.fn "R2"
          s!"a row is pushed onto {table.describe}, where no key counter is in scope"
    | .region region =>
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
          s!"{table.describe} is spliced by other than exactly one row"
    | _ => fail env.fn "R3"
        s!"{table.describe} takes a splice that is not a single-row removal"
  else
    fail env.fn "R1" s!"'{name}' is called on {table.describe}"

mutual

  /-- Check one expression and collect the identifier census R5 rules on. A
  bare row table or region record is rejected right here, in the case that
  builds one; the positions the rules approve reach their children without
  routing the table itself back through this function. -/
  private def auditExpr (env : Env) : Expr → Except Error (List (Ident × Use))
    | .ident name =>
        if env.tables.contains name then
          fail env.fn "R1" s!"the row table parameter '{name.raw}' escapes into a value position"
        else pure [(name, .other)]
    | .literal _ => pure []
    | .unary _ value => auditExpr env value
    | .binary _ left right => do
        pure ((← auditExpr env left) ++ (← auditExpr env right))
    | .conditional condition yes no => do
        pure ((← auditExpr env condition) ++ (← auditExpr env yes) ++
          (← auditExpr env no))
    | .array values => auditArgs env values
    /- A rebuild push: `kept["push"](row)` where `row` is a `for`-of binding
    over some table and `kept` is not itself a row table. Neither name counts
    as an ordinary use. -/
    | .call (.index (.ident target) (.literal (.string name)))
        (.cons (.ident value) .nil) =>
        if name == "push" && !env.tables.contains target then
          match env.rows.lookup value with
          | some table => pure [(target, .keptPush table)]
          | none =>
              if env.tables.contains value then
                fail env.fn "R1"
                  s!"the row table parameter '{value.raw}' escapes into a value position"
              else pure [(target, .other), (value, .other)]
        else
          match tableOf? env (.ident target) with
          | some table => do
              pure ((← auditRowCall env table name (.cons (.ident value) .nil)) ++
                (← auditArgs env (.cons (.ident value) .nil)))
          | none =>
              if env.tables.contains value then
                fail env.fn "R1"
                  s!"the row table parameter '{value.raw}' escapes into a value position"
              else pure [(target, .other), (value, .other)]
    | .call (.index target (.literal (.string name))) args =>
        match tableOf? env target with
        | some table => do
            pure ((← auditRowCall env table name args) ++ (← auditArgs env args))
        | none => do
            let object ← auditExpr env target
            /- R1: a table may be handed to its own region's host handle, and
            the ADR-0094 contract picks it up on the far side. -/
            let carried ←
              if (handle? target).isSome then auditTableArgs env args
              else auditArgs env args
            pure (object ++ carried)
    | .call (.ident name) args =>
        /- R1/R0: a table may be handed to a function this module declares,
        because R0's fixpoint has already made that function's parameter a row
        table. An imported callee has no body, so it is not an approved
        position and `auditArgs` rejects the table. -/
        if env.locals.contains name then auditTableArgs env args
        else do pure ((name, .other) :: (← auditArgs env args))
    | .call callee args => do
        pure ((← auditExpr env callee) ++ (← auditArgs env args))
    | .index target index =>
        match tableOf? env (.index target index), recordRef? (.index target index) with
        | some table, _ =>
            fail env.fn "R1" s!"{table.describe} escapes into a value position"
        | _, some region =>
            fail env.fn "R1" s!"region {region}'s record escapes into a value position"
        | _, _ =>
            if (contextRef? target).isSome then
              fail env.fn "R0" "the region record is reached by indexing the context twice"
            else if (recordRef? target).isSome then
              auditExpr env index
            else
              match tableOf? env target, index with
              | some table, .literal (.string name) =>
                  if name == "length" then pure []
                  else fail env.fn "R1"
                    s!"'{name}' is read off {table.describe} outside a call"
              | some _, _ => auditExpr env index
              | none, _ => do
                  pure ((← auditExpr env target) ++ (← auditExpr env index))

  private def auditArgs (env : Env) : Args → Except Error (List (Ident × Use))
    | .nil => pure []
    | .cons head tail => do pure ((← auditExpr env head) ++ (← auditArgs env tail))

  /-- Arguments of a callee a row table may be handed to. -/
  private def auditTableArgs (env : Env) : Args → Except Error (List (Ident × Use))
    | .nil => pure []
    | .cons head tail => do
        let here ← if (tableOf? env head).isSome then pure [] else auditExpr env head
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
        else if env.tables.contains name then
          fail env.fn "R4" s!"the row table parameter '{name.raw}' is rebound"
        else do pure ((name, .other) :: (← auditExpr env value))
    | .assign (.index base index) value =>
        match slotRef? (.index base index) with
        | some (region, 1) =>
            match value with
            | .ident name =>
                if env.tables.contains name then
                  fail env.fn "R5"
                    s!"region {region}'s row table is replaced by the row table parameter '{name.raw}'"
                else pure [(name, .tableAssign region)]
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
            match tableOf? env base, rowRef? env base, number? index with
            | some table, _, _ =>
                fail env.fn "R4" s!"a row of {table.describe} is replaced in place"
            | none, some table, some 0 =>
                fail env.fn "R4" s!"a row of {table.describe} has its key slot assigned"
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
        match tableOf? env iterable with
        | some table =>
            auditBlock { env with rows := (binding, table) :: env.rows } body
        | none => do
            pure ((← auditExpr env iterable) ++ (← auditBlock env body))
    | .whileLoop condition body => do
        pure ((← auditExpr env condition) ++ (← auditBlock env body))
    | .return value => auditExpr env value

  private def auditBlock (env : Env) : Block → Except Error (List (Ident × Use))
    | .nil => pure []
    | .cons head tail => do
        let here ← auditStmt env head
        let next := match boundRow? env head with
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
    mine.count (Use.keptPush (.region region)) == 1 &&
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

private def auditFunction (regionSlot : Nat) (locals : List Ident) (sites : List Site)
    (value : Function) : Except Error Unit := do
  let env : Env := {
    fn := value.name.raw, regionSlot, rows := [], locals
    tables := tableParams sites value.name 0 value.params.toList }
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

private def functionsOf (module : Module) : List Function :=
  module.declarations.toList.map fun declaration =>
    match declaration with
    | .function value => value

private def paramBudget (functions : List Function) : Nat :=
  functions.foldl (fun total value => total + value.params.size) 0

/-- The ADR-0093 audit over one emitted component module. `regionSlot` is the
context slot the component's region record occupies, which is what makes R0's
first clause — every row table the module names itself is spelled
`regions[r][1]` — checkable; R0's second clause is the ADR-0095 fixpoint
computed here, before any rule is applied. -/
def audit (regionSlot : Nat) (module : Module) : Except Error Unit := do
  let functions := functionsOf module
  let locals := functions.map (·.name)
  let sites := propagate locals functions (paramBudget functions + 1) []
  /- R0: the rules below approve handing a table to any function this module
  declares, on the strength of that function's parameter having been made a
  table. If the fixpoint had not converged, some parameter would be missing
  and the approval would be unbacked, so stability is asserted rather than
  inferred from the budget. -/
  unless (sweep locals functions sites).length == sites.length do
    throw {
      code := "LRX-BE-036"
      message :=
        "row order audit (R0) in the module: the row table parameters do not settle, so a table can reach a parameter the rules were not applied to"
    }
  for value in functions do
    auditFunction regionSlot locals sites value

end LeanRx.Backend.RowOrder
