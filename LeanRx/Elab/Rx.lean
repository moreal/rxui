import LeanRx.Core.RxOps
import Lean.Elab.Term
import Lean.Elab.SyntheticMVars

open Lean Elab Meta

/-! `rx%` stages ordinary Lean expression syntax into the closed `RxExpr` core.

The macro layer maps operators, literals, conditionals, and `s!` interpolation
onto the typeclass-directed smart constructors in `LeanRx.Core.RxOps`, so the
staged tree is exactly the one a hand-written `RxExpr` term would build. Leaves
fall through to a term elaborator that stages schema fields as reads, passes
staged expressions through unchanged, and lifts closed scalar values into
literals; anything else is rejected with a stable diagnostic. -/

namespace LeanRxDsl

/-- Stage one `rx%` leaf from its elaborated type. -/
elab "leanrx_rx_atom% " value:term : term <= expectedType => do
  let type ← withoutModifyingState <| Term.withoutErrToSorry do
    let expression ← Term.elabTerm value none
    Term.synthesizeSyntheticMVarsNoPostponing
    whnf (← instantiateMVars (← inferType expression))
  let scalar := type.isConstOf ``Bool || type.isConstOf ``Int ||
    type.isConstOf ``Nat || type.isConstOf ``String
  let wrapped ←
    if type.isAppOf ``LeanRx.Field then `(LeanRx.RxExpr.read $value)
    else if type.isAppOf ``LeanRx.RxExpr then pure value
    else if type.isAppOf ``LeanRx.ScalarLiteral then `(LeanRx.RxExpr.literal $value)
    else if scalar then `(LeanRx.RxExpr.liftLit $value)
    else throwErrorAt value
      "error[LRX-RX-001]: rx% cannot stage a value of type {type}; expected a \
       schema field, a staged expression, or a Bool/Int/Nat/String scalar"
  Term.elabTerm wrapped expectedType

scoped syntax "rx% " term : term

/- The generic leaf rule is registered first so every specific rule below is
tried before it; unhandled syntax reaches the typed leaf elaborator intact. -/
macro_rules
  | `(rx% $value:term) => `(leanrx_rx_atom% $value)

macro_rules
  | `(rx% ($value)) => `(rx% $value)
  | `(rx% $left + $right) => `(LeanRx.RxExpr.addOp (rx% $left) (rx% $right))
  | `(rx% $left - $right) => `(LeanRx.RxExpr.subOp (rx% $left) (rx% $right))
  | `(rx% $left * $right) => `(LeanRx.RxExpr.mulOp (rx% $left) (rx% $right))
  | `(rx% $left % $right) => `(LeanRx.RxExpr.modOp (rx% $left) (rx% $right))
  | `(rx% $left < $right) => `(LeanRx.RxExpr.ltOp (rx% $left) (rx% $right))
  | `(rx% $left ≤ $right) => `(LeanRx.RxExpr.leOp (rx% $left) (rx% $right))
  | `(rx% $left > $right) => `(LeanRx.RxExpr.ltOp (rx% $right) (rx% $left))
  | `(rx% $left ≥ $right) => `(LeanRx.RxExpr.leOp (rx% $right) (rx% $left))
  | `(rx% $left == $right) => `(LeanRx.RxExpr.eqOp (rx% $left) (rx% $right))
  | `(rx% $left != $right) => `(LeanRx.RxExpr.neOp (rx% $left) (rx% $right))
  | `(rx% $left && $right) => `(LeanRx.RxExpr.andOp (rx% $left) (rx% $right))
  | `(rx% $left || $right) => `(LeanRx.RxExpr.orOp (rx% $left) (rx% $right))
  | `(rx% !$value) => `(LeanRx.RxExpr.notOp (rx% $value))
  | `(rx% -$value) => `(LeanRx.RxExpr.negOp (rx% $value))
  | `(rx% $left ++ $right) => `(LeanRx.RxExpr.appendOp (rx% $left) (rx% $right))
  | `(rx% if $condition then $yes else $no) =>
      `(LeanRx.RxExpr.condOp (rx% $condition) (rx% $yes) (rx% $no))
  | `(rx% toString $value) => `(LeanRx.RxExpr.toText (rx% $value))
  | `(rx% $value:num) => `(LeanRx.RxExpr.numLit $value)
  | `(rx% $value:str) => `(LeanRx.RxExpr.strLit $value)
  | `(rx% true) => `(LeanRx.RxExpr.boolLit true)
  | `(rx% false) => `(LeanRx.RxExpr.boolLit false)
  | `(rx% s! $interpStr) => do
      let staged ← TSyntax.expandInterpolatedStrChunks interpStr.raw.getArgs
        (fun left right => `(LeanRx.RxExpr.appendOp $(⟨left⟩) $(⟨right⟩)))
        (fun value => `(LeanRx.RxExpr.toText (rx% $(⟨value⟩))))
        (fun chunk => `(LeanRx.RxExpr.strLit $(Syntax.mkStrLit chunk)))
      pure staged

end LeanRxDsl
