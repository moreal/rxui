import LeanRx.Component.Model
import LeanRx.Elab.View
import Lean.Elab.Command
import Lean.Meta.Eval

open Lean Elab Command

namespace LeanRxDsl

private def normalizedFileName : CommandElabM String := do
  let fileName ← getFileName
  let currentDir ← IO.currentDir
  let rootPrefix := currentDir.toString ++ "/"
  pure <| if fileName.startsWith rootPrefix then
    (fileName.drop rootPrefix.length).toString
  else fileName

private def sourceSpanTerm (stx : Syntax) : CommandElabM (TSyntax `term) := do
  let fileMap ← getFileMap
  let fileName := Syntax.mkStrLit (← normalizedFileName)
  let start := stx.getPos?.getD 0
  let stop := stx.getTailPos?.getD start
  let startPosition := fileMap.toPosition start
  let stopPosition := fileMap.toPosition stop
  let startLine := Syntax.mkNumLit (toString startPosition.line)
  let startColumn := Syntax.mkNumLit (toString (startPosition.column + 1))
  let startByte := Syntax.mkNumLit (toString start.byteIdx)
  let stopLine := Syntax.mkNumLit (toString stopPosition.line)
  let stopColumn := Syntax.mkNumLit (toString (stopPosition.column + 1))
  let stopByte := Syntax.mkNumLit (toString stop.byteIdx)
  `(LeanRx.SourceSpan.mk $fileName
      (LeanRx.SourcePos.mk $startLine $startColumn $startByte)
      (LeanRx.SourcePos.mk $stopLine $stopColumn $stopByte))

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
        let itemSpan ← sourceSpanTerm item
        match item with
        | `(leanrxComponentItem| state $itemName:ident := $value:term;) =>
            values := values.push (← `(LeanRx.ValueSpec.withSpan $value $itemSpan))
            let declarationName := Syntax.mkStrLit itemName.getId.toString
            declarations := declarations.push (← `(LeanRx.SurfaceDecl.mk
              LeanRx.SurfaceRole.state $declarationName $itemSpan))
        | `(leanrxComponentItem| derived $itemName:ident := $value:term;) =>
            values := values.push (← `(LeanRx.ValueSpec.withSpan $value $itemSpan))
            let declarationName := Syntax.mkStrLit itemName.getId.toString
            declarations := declarations.push (← `(LeanRx.SurfaceDecl.mk
              LeanRx.SurfaceRole.derived $declarationName $itemSpan))
        | `(leanrxComponentItem| event $itemName:ident := $value:term;) =>
            events := events.push (← `(LeanRx.EventSpec.withSpan $value $itemSpan))
            let declarationName := Syntax.mkStrLit itemName.getId.toString
            declarations := declarations.push (← `(LeanRx.SurfaceDecl.mk
              LeanRx.SurfaceRole.event $declarationName $itemSpan))
        | `(leanrxComponentItem| view := $value:term;) =>
            if viewTerm?.isSome then
              throwErrorAt item "error[LRX-ELAB-002]: component must have exactly one view"
            viewTerm? := some (← `(LeanRx.View.withSpan $value $itemSpan))
        | _ => throwErrorAt item "error[LRX-ELAB-003]: malformed component item"
      let viewTerm ← viewTerm?.getDM <| throwErrorAt name
        "error[LRX-ELAB-001]: component requires a view declaration"
      let schemaName := mkIdent (name.getId.appendAfter "_schema")
      let specName := mkIdent (name.getId.appendAfter "_spec")
      let checkName := mkIdent (name.getId.appendAfter "_check")
      let declarationsName := mkIdent (name.getId.appendAfter "_declarations")
      let componentName : TSyntax `term := ⟨Syntax.mkStrLit name.getId.toString⟩
      let componentSpan ← sourceSpanTerm name
      elabCommand (← `(abbrev $schemaName : LeanRx.Schema := $schemaTerm))
      elabCommand (← `(def $declarationsName : List LeanRx.SurfaceDecl := [$declarations,*]))
      elabCommand (← `(abbrev $specName : LeanRx.ComponentSpec $schemaName :=
        LeanRx.ComponentSpec.mk $componentName #[$values,*] #[$events,*]
          $viewTerm #[$declarations,*] $componentSpan))
      elabCommand (← `(abbrev $checkName := LeanRx.ComponentSpec.check $specName))
      let messageTerm ← `(term| LeanRx.ComponentSpec.validationMessage $specName)
      let message : String ← liftTermElabM do
        let expression ← Term.elabTermEnsuringType messageTerm (mkConst ``String)
        Term.synthesizeSyntheticMVarsNoPostponing
        let expression ← instantiateMVars expression
        /- This isolated compile-time evaluation reports the total public validator's
        exact structured message; generated unsafe wrappers are audited by name. -/
        unsafe Meta.evalExpr (checkMeta := false) String (mkConst ``String) expression
      unless message.isEmpty do
        throwErrorAt name message

end LeanRxDsl
