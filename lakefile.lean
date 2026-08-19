import Lake

open Lake DSL

package leanrx where
  version := v!"0.1.0"
  fixedToolchain := true
  moreLeanArgs := #["-E", "hasSorry"]

lean_lib LeanRx

lean_lib LeanRxTest where
  roots := #[`Test.Policy.EnvironmentAudit, `Test.AxiomManifest, `Test.Core.Schema,
    `Test.Core.Dependency, `Test.Core.Store, `Test.Core.RuntimeRep, `Test.Core.Equality,
    `Test.Core.Expr, `Test.Proofs.DependencySound]

@[default_target]
lean_exe leanrx_test where
  root := `Test.Main
