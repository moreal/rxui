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
    `Test.Core.Expr, `Test.Core.ExprPrimitives, `Test.Proofs.DependencySound,
    `Test.Graph.Model, `Test.Graph.Build, `Test.Graph.Topological, `Test.Graph.Properties,
    `Test.Graph.Serialize,
    `Test.Graph.IntProgram,
    `Test.Backend.JsAst,
    `Test.Semantics.Store, `Test.Semantics.Fixtures, `Test.Semantics.Reference,
    `Test.Semantics.Optimized, `Test.Proofs.PropagationSound]

@[default_target]
lean_exe leanrx_test where
  root := `Test.Main

lean_exe leanrx_expr_playground where
  root := `examples.ExpressionPlayground

lean_exe leanrx_graph_lab where
  root := `examples.GraphLab

lean_exe leanrx_graph_properties where
  root := `Test.Graph.PropertyMain
