import LeanRx.Component.Model
import LeanRx.Elab.View
import Lean.Elab.Command
import Lean.Meta.Eval

open Lean Elab Command

namespace LeanRxDsl

declare_syntax_cat leanrxComponentItem
scoped syntax "state" ident ":=" term ";" : leanrxComponentItem
scoped syntax "derived" ident ":=" term ";" : leanrxComponentItem
scoped syntax "event" ident ":=" term ";" : leanrxComponentItem
scoped syntax "view" ":=" term ";" : leanrxComponentItem

open scoped LeanRxDsl

scoped elab (name := leanrxComponent) "component" name:ident "(" "schema" ":=" schemaTerm:term ")"
    "where" "{" items:leanrxComponentItem* "}" : command => do
      let mut values : Array (TSyntax `term) := #[]
      let mut events : Array (TSyntax `term) := #[]
      let mut declarations : Array (TSyntax `term) := #[]
      let mut viewTerm? : Option (TSyntax `term) := none
      for item in items do
        match item with
        | `(leanrxComponentItem| state $itemName:ident := $value:term;) =>
            values := values.push value
            declarations := declarations.push ⟨Syntax.mkStrLit s!"state:{itemName.getId}"⟩
        | `(leanrxComponentItem| derived $itemName:ident := $value:term;) =>
            values := values.push value
            declarations := declarations.push ⟨Syntax.mkStrLit s!"derived:{itemName.getId}"⟩
        | `(leanrxComponentItem| event $itemName:ident := $value:term;) =>
            events := events.push value
            declarations := declarations.push ⟨Syntax.mkStrLit s!"event:{itemName.getId}"⟩
        | `(leanrxComponentItem| view := $value:term;) =>
            if viewTerm?.isSome then
              throwErrorAt item "error[LRX-ELAB-002]: component must have exactly one view"
            viewTerm? := some value
        | _ => throwErrorAt item "error[LRX-ELAB-003]: malformed component item"
      let viewTerm ← viewTerm?.getDM <| throwErrorAt name
        "error[LRX-ELAB-001]: component requires a view declaration"
      let schemaName := mkIdent (name.getId.appendAfter "_schema")
      let specName := mkIdent (name.getId.appendAfter "_spec")
      let checkName := mkIdent (name.getId.appendAfter "_check")
      let declarationsName := mkIdent (name.getId.appendAfter "_declarations")
      let componentName : TSyntax `term := ⟨Syntax.mkStrLit name.getId.toString⟩
      elabCommand (← `(abbrev $schemaName : LeanRx.Schema := $schemaTerm))
      elabCommand (← `(def $declarationsName : List String := [$declarations,*]))
      elabCommand (← `(abbrev $specName : LeanRx.ComponentSpec $schemaName :=
        LeanRx.ComponentSpec.mk $componentName #[$values,*] #[$events,*]
          $viewTerm LeanRx.SourceSpan.generated))
      elabCommand (← `(abbrev $checkName := LeanRx.ComponentSpec.check $specName))
      let validTerm ← `(term| Except.isOk $checkName)
      let valid : Bool ← liftTermElabM do
        let expression ← Term.elabTermEnsuringType validTerm (mkConst ``Bool)
        Term.synthesizeSyntheticMVarsNoPostponing
        let expression ← instantiateMVars expression
        unsafe Meta.evalExpr (checkMeta := false) Bool (mkConst ``Bool) expression
      unless valid do
        throwErrorAt name (
          "error[LRX-ELAB-004]: generated component failed structural validation; " ++
          s!"inspect {checkName.getId} for the checked diagnostic")

end LeanRxDsl
