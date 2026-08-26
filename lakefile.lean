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
    `Test.Backend.JsCompact,
    `Test.IR.Erasure,
    `Test.Lower.RxExpr,
    `Test.Backend.Scalar,
    `Test.Backend.FormDom,
    `Test.Backend.Component,
    `Test.Backend.Tabs,
    `Test.Backend.Temperature,
    `Test.Backend.ValidatedForm,
    `Test.Backend.Todo,
    `Test.Backend.Notes,
    `Test.Backend.IssueBrowser,
    `Test.Backend.Grid,
    `Test.Backend.JsFrameworkBenchmark,
    `Test.View.Model,
    `Test.Component.Model,
    `Test.Component.Dependent,
    `Test.Component.DiamondLab,
    `Test.Component.DocsSite,
    `Test.Form.Validation,
    `Test.Form.Dom,
    `Test.Form.Temperature,
    `Test.Form.Validated,
    `Test.Region.Conditional,
    `Test.Region.Positional,
    `Test.Region.Keyed,
    `Test.Collection.Delta,
    `Test.Grid.Model,
    `Test.Grid.Component,
    `Test.JsFrameworkBenchmark.Model,
    `Test.Todo.Model,
    `Test.Effect.Command,
    `Test.Effect.Resource,
    `Test.Notes.Model,
    `Test.IssueBrowser.Model,
    `Test.Elab.Component,
    `Test.Elab.Rx,
    `Test.Elab.TodoSurface,
    `Test.Elab.ViewSurface,
    `Test.Docs.LanguageGuide,
    `Test.Cli.Model,
    `Test.Cli.AtomicOutput,
    `Test.Semantics.Store, `Test.Semantics.Fixtures, `Test.Semantics.Reference,
    `Test.Semantics.Optimized, `Test.Proofs.PropagationSound]

lean_lib LeanRxExamples where
  roots := #[`examples.ExpressionPlayground, `examples.GraphFixtures,
    `examples.Counter, `examples.CounterBuild,
    `examples.DiamondLab, `examples.DiamondLabBuild,
    `examples.BranchLab, `examples.BranchLabBuild,
    `examples.ToggleLab, `examples.ToggleLabBuild,
    `examples.EchoLab, `examples.EchoLabBuild,
    `examples.FilterLab, `examples.FilterLabBuild,
    `examples.NestLab, `examples.NestLabBuild, `examples.DependentTabs,
    `examples.DependentTabsBuild, `examples.TemperatureConverter,
    `examples.TemperatureConverterBuild, `examples.ValidatedForm,
    `examples.ValidatedFormBuild, `examples.TodoMVC, `examples.TodoMVCBuild,
    `examples.Notes, `examples.NotesBuild, `examples.IssueBrowser,
    `examples.IssueBrowserBuild, `examples.DataGrid, `examples.DataGridBuild,
    `examples.JsFrameworkBenchmark, `examples.JsFrameworkBenchmarkBuild,
    `examples.LeanRxDocs, `examples.LeanRxDocsBuild]

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

lean_exe leanrx_echo_js where
  root := `examples.EchoLabMain

lean_exe leanrx_nest_js where
  root := `examples.NestLabMain

lean_exe leanrx_filter_js where
  root := `examples.FilterLabMain

lean_exe leanrx_branch_js where
  root := `examples.BranchLabMain

lean_exe leanrx_toggle_js where
  root := `examples.ToggleLabMain

lean_exe leanrx_tabs_js where
  root := `examples.DependentTabsMain

lean_exe leanrx_temperature_js where
  root := `examples.TemperatureConverterMain

lean_exe leanrx_validated_form_js where
  root := `examples.ValidatedFormMain

lean_exe leanrx_todo_js where
  root := `examples.TodoMVCMain

lean_exe leanrx_notes_js where
  root := `examples.NotesMain

lean_exe leanrx_issue_browser_js where
  root := `examples.IssueBrowserMain

lean_exe leanrx_data_grid_js where
  root := `examples.DataGridMain

lean_exe leanrx_js_framework_benchmark where
  root := `examples.JsFrameworkBenchmarkMain

lean_exe leanrx_docs_js where
  root := `examples.LeanRxDocsMain

lean_exe leanrx_graph_bench where
  root := `bench.SmallGraph

lean_exe leanrx_grid_bench where
  root := `bench.DataGrid

lean_exe leanrx where
  root := `LeanRx.Cli.Main
