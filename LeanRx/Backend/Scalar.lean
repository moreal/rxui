import LeanRx.Backend.JsName
import LeanRx.IR.Reactive

namespace LeanRx.Backend.Scalar

open LeanRx.Js

inductive Helper where
  | intMod
  | natSub
  | natMod
deriving Repr, BEq, DecidableEq

structure HelperBinding where
  helper : Helper
  name : Ident
deriving Repr, BEq

structure Emitted where
  module : Module
  exportName : Ident
deriving Repr, BEq

private def addHelper (helper : Helper) (helpers : List Helper) : List Helper :=
  if helpers.contains helper then helpers else helpers ++ [helper]

private def mergeHelpers (left right : List Helper) : List Helper :=
  right.foldl (fun helpers helper => addHelper helper helpers) left

def helpers : {α : Type} → ReactiveIR.Expr α → List Helper
  | _, .literal _ => []
  | _, .input _ _ _ => []
  | _, .unary _ value => helpers value
  | _, .binary op left right =>
      let nested := mergeHelpers (helpers left) (helpers right)
      match op with
      | .intMod => addHelper .intMod nested
      | .natSub => addHelper .natSub nested
      | .natMod => addHelper .natMod nested
      | _ => nested
  | _, .conditional condition yes no =>
      mergeHelpers (mergeHelpers (helpers condition) (helpers yes)) (helpers no)

private def helperRequested : Helper → String
  | .intMod => "$lrx_intMod"
  | .natSub => "$lrx_natSub"
  | .natMod => "$lrx_natMod"

private def allocateHelpers : List Helper → NameAllocator →
    Except Error (List HelperBinding × NameAllocator)
  | [], allocator => pure ([], allocator)
  | helper :: rest, allocator => do
      let (name, allocator) ← allocator.allocate (helperRequested helper)
      let (bindings, allocator) ← allocateHelpers rest allocator
      pure ({ helper, name } :: bindings, allocator)

private def helperName (bindings : List HelperBinding) (helper : Helper) : Except Error Ident :=
  match bindings.find? (·.helper == helper) with
  | some binding => pure binding.name
  | none => .error {
      code := "LRX-JS-014"
      message := "scalar lowering is missing a required runtime helper binding"
    }

private def input (inputs : Array Ident) (index : Nat) : Except Error Ident :=
  match inputs[index]? with
  | some name => pure name
  | none => .error {
      code := "LRX-JS-013"
      message := s!"Reactive IR input index {index} is outside the evaluator parameter list"
    }

private def literal : {α : Type} → ReactiveIR.Literal α → Js.Literal
  | _, .bool value => .boolean value
  | _, .string value => .string value
  | _, .int value => .bigint value
  | _, .nat value => .bigint (Int.ofNat value)

private inductive UnaryPlan where
  | direct (op : UnaryOp)
  | identity
  | displayString

private def unary : {α β : Type} → ReactiveIR.Unary α β → UnaryPlan
  | _, _, .boolNot => .direct .not
  | _, _, .intNeg => .direct .neg
  | _, _, .natToInt => .identity
  | _, _, .intToString => .displayString
  | _, _, .natToString => .displayString

private def directBinary : {α β γ : Type} → ReactiveIR.Binary α β γ → Option BinaryOp
  | _, _, _, .intAdd => some .add
  | _, _, _, .intSub => some .sub
  | _, _, _, .intMul => some .mul
  | _, _, _, .intMod => none
  | _, _, _, .intEq => some .eq
  | _, _, _, .intLt => some .lt
  | _, _, _, .intLe => some .le
  | _, _, _, .natAdd => some .add
  | _, _, _, .natSub => none
  | _, _, _, .natMul => some .mul
  | _, _, _, .natMod => none
  | _, _, _, .natEq => some .eq
  | _, _, _, .natLt => some .lt
  | _, _, _, .natLe => some .le
  | _, _, _, .boolAnd => some .and
  | _, _, _, .boolOr => some .or
  | _, _, _, .stringAppend => some .add
  | _, _, _, .stringEq => some .eq

private def binaryHelper : {α β γ : Type} → ReactiveIR.Binary α β γ → Option Helper
  | _, _, _, .intMod => some .intMod
  | _, _, _, .natSub => some .natSub
  | _, _, _, .natMod => some .natMod
  | _, _, _, _ => none

def expr (inputs : Array Ident) (bindings : List HelperBinding) :
    {α : Type} → ReactiveIR.Expr α → Except Error Js.Expr
  | _, .literal value => pure (.literal (literal value))
  | _, .input _ index _ => do pure (.ident (← input inputs index))
  | _, .unary op value => do
      match unary op with
      | .identity => expr inputs bindings value
      | .direct jsOp => pure (.unary jsOp (← expr inputs bindings value))
      | .displayString =>
          let stringName ← Ident.checked "String"
          pure (.call (.ident stringName) <| .ofList [← expr inputs bindings value])
  | _, .binary op left right => do
      let loweredLeft ← expr inputs bindings left
      let loweredRight ← expr inputs bindings right
      match directBinary op with
      | some jsOp => pure (.binary jsOp loweredLeft loweredRight)
      | none =>
          match binaryHelper op with
          | some required =>
              let helper ← helperName bindings required
              pure (.call (.ident helper) <| .ofList [loweredLeft, loweredRight])
          | none => .error {
              code := "LRX-JS-015"
              message := "Reactive IR binary primitive has no JavaScript lowering"
            }
  | _, .conditional condition yes no => do
      pure (.conditional (← expr inputs bindings condition)
        (← expr inputs bindings yes) (← expr inputs bindings no))

private def internalIdent (value : String) : Except Error Ident :=
  Ident.checked value

private def helperFunction (binding : HelperBinding) : Except Error Function := do
  let left ← internalIdent "left"
  let right ← internalIdent "right"
  let leftExpr : Js.Expr := .ident left
  let rightExpr : Js.Expr := .ident right
  let zero : Js.Expr := .literal (.bigint 0)
  let body := match binding.helper with
    | .intMod =>
        let magnitude := Js.Expr.conditional (.binary .lt rightExpr zero)
          (.unary .neg rightExpr) rightExpr
        let remainder := Js.Expr.binary .rem leftExpr magnitude
        let normalized := Js.Expr.binary .rem (.binary .add remainder magnitude) magnitude
        Js.Expr.conditional (.binary .eq rightExpr zero) leftExpr normalized
    | .natSub =>
        Js.Expr.conditional (.binary .le rightExpr leftExpr)
          (.binary .sub leftExpr rightExpr) zero
    | .natMod =>
        Js.Expr.conditional (.binary .eq rightExpr zero) leftExpr
          (.binary .rem leftExpr rightExpr)
  pure { name := binding.name, params := #[left, right], body := #[.return body] }

private def allocateInputs : List String → NameAllocator →
    Except Error (List Ident × NameAllocator)
  | [], allocator => pure ([], allocator)
  | requested :: rest, allocator => do
      let (name, allocator) ← allocator.allocate requested
      let (names, allocator) ← allocateInputs rest allocator
      pure (name :: names, allocator)

/-- Emit one pure ESM evaluator from typed Reactive IR. -/
def moduleFor (requestedExport : String) (inputNames : Array String)
    (value : ReactiveIR.Expr α) : Except Error Emitted := do
  let (bindings, allocator) ← allocateHelpers (helpers value) {}
  let (exportName, allocator) ← allocator.allocate requestedExport
  let (inputs, _) ← allocateInputs inputNames.toList allocator
  let result ← expr inputs.toArray bindings value
  let helperDecls ← bindings.mapM fun binding => do
    pure (Decl.function (← helperFunction binding))
  let evaluator : Function :=
    { name := exportName, params := inputs.toArray, body := #[.return result] }
  let module : Module :=
    { declarations := (helperDecls ++ [Decl.function evaluator]).toArray
      exports := #[{ localName := exportName, exportName }] }
  module.validate
  pure { module, exportName }

end LeanRx.Backend.Scalar
