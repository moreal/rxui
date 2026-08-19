import Test.AxiomManifest
import Test.Core.Schema
import Test.Core.Dependency
import Test.Core.Store
import Test.Core.RuntimeRep
import Test.Core.Equality
import Test.Core.Expr
import Test.Core.ExprPrimitives
import Test.Proofs.DependencySound
import Test.Graph.Model
import Test.Graph.Build
import Test.Graph.Topological
import Test.Graph.Serialize
import Test.Graph.IntProgram
import Test.Backend.JsAst
import Test.Backend.JsName
import Test.Backend.JsPrinter
import Test.IR.Erasure
import Test.Lower.RxExpr
import Test.Backend.Scalar
import Test.Backend.Component
import Test.Backend.Tabs
import Test.View.Model
import Test.Component.Model
import Test.Component.Dependent
import Test.Component.DiamondLab
import Test.Elab.Component
import Test.Cli.Model
import Test.Cli.AtomicOutput
import Test.Semantics.Store
import Test.Semantics.Reference
import Test.Semantics.Optimized
import Test.Proofs.PropagationSound

private def assertEq [BEq α] [ToString α] (expected actual : α) : IO Unit :=
  unless expected == actual do
    throw <| IO.userError s!"expected {expected}, got {actual}"

def main : IO Unit := do
  assertEq "0.1.0-dev" LeanRx.version
  assertEq "" LeanRx.SourceSpan.generated.file
  assertEq 0 LeanRx.SourceSpan.generated.start.byteOffset
  LeanRxTest.Schema.run
  LeanRxTest.Dependency.run
  LeanRxTest.Store.run
  LeanRxTest.RuntimeRep.run
  LeanRxTest.Equality.run
  LeanRxTest.Expr.run
  LeanRxTest.ExprPrimitives.run
  LeanRxTest.DependencySound.run
  LeanRxTest.Graph.Model.run
  LeanRxTest.Graph.Build.run
  LeanRxTest.Graph.Topological.run
  LeanRxTest.Graph.Serialize.run
  LeanRxTest.Graph.IntProgram.run
  LeanRxTest.Backend.JsAst.run
  LeanRxTest.Backend.JsName.run
  LeanRxTest.Backend.JsPrinter.run
  LeanRxTest.IR.Erasure.run
  LeanRxTest.Lower.RxExpr.run
  LeanRxTest.Backend.Scalar.run
  LeanRxTest.Backend.Component.run
  LeanRxTest.Backend.Tabs.run
  LeanRxTest.View.Model.run
  LeanRxTest.Component.Model.run
  LeanRxTest.Component.Dependent.run
  LeanRxTest.Component.DiamondLab.run
  LeanRxTest.Elab.Component.run
  LeanRxTest.Cli.Model.run
  LeanRxTest.Cli.AtomicOutput.run
  LeanRxTest.Semantics.Store.run
  LeanRxTest.Semantics.Reference.run
  LeanRxTest.Semantics.Optimized.run
  LeanRxTest.PropagationSound.run
  IO.println "LeanRx native smoke tests passed"
