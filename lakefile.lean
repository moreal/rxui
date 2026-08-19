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
    `Test.Backend.JsName,
    `Test.Backend.JsPrinter,
    `Test.IR.Erasure,
    `Test.Lower.RxExpr,
    `Test.Backend.Scalar,
    `Test.Backend.Component,
    `Test.Backend.Tabs,
    `Test.Backend.Temperature,
    `Test.Backend.ValidatedForm,
    `Test.View.Model,
    `Test.Component.Model,
    `Test.Component.Dependent,
    `Test.Component.DiamondLab,
    `Test.Form.Validation,
    `Test.Form.Dom,
    `Test.Form.Temperature,
    `Test.Form.Validated,
    `Test.Elab.Component,
    `Test.Cli.Model,
    `Test.Cli.AtomicOutput,
    `Test.Semantics.Store, `Test.Semantics.Fixtures, `Test.Semantics.Reference,
    `Test.Semantics.Optimized, `Test.Proofs.PropagationSound]

lean_lib LeanRxExamples where
  roots := #[`examples.ExpressionPlayground, `examples.GraphFixtures,
    `examples.Counter, `examples.CounterBuild,
    `examples.DiamondLab, `examples.DiamondLabBuild, `examples.DependentTabs,
    `examples.DependentTabsBuild, `examples.TemperatureConverter,
    `examples.TemperatureConverterBuild]

@[default_target]
lean_exe leanrx_test where
  root := `Test.Main

lean_exe leanrx_expr_playground where
  root := `examples.ExpressionPlaygroundMain

lean_exe leanrx_expr_playground_js where
  root := `examples.ExpressionPlaygroundJs

lean_exe leanrx_graph_lab where
  root := `examples.GraphLab

lean_exe leanrx_graph_properties where
  root := `Test.Graph.PropertyMain

lean_exe leanrx_generate_differential where
  root := `Test.Backend.GenerateDifferential

lean_exe leanrx_counter_js where
  root := `examples.CounterMain

lean_exe leanrx_diamond_js where
  root := `examples.DiamondLabMain

lean_exe leanrx_tabs_js where
  root := `examples.DependentTabsMain

lean_exe leanrx_temperature_js where
  root := `examples.TemperatureConverterMain

lean_exe leanrx_graph_bench where
  root := `bench.SmallGraph

lean_exe leanrx where
  root := `LeanRx.Cli.Main
