import Test.AxiomManifest
import Test.Core.Schema
import Test.Core.Dependency
import Test.Core.Store
import Test.Core.RuntimeRep
import Test.Core.Equality
import Test.Core.Expr
import Test.Core.ExprPrimitives
import Test.Proofs.DependencySound

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
  IO.println "LeanRx native smoke tests passed"
