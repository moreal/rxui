import LeanRx.Backend.JsFrameworkBenchmark

namespace LeanRxTest.Backend.JsFrameworkBenchmark

open LeanRx LeanRx.JsFrameworkBenchmark

private def assertEq [BEq α] [ToString α] (expected actual : α) : IO Unit :=
  unless expected == actual do
    throw <| IO.userError s!"expected {expected}, got {actual}"

def run : IO Unit := do
  let checked ← match (Spec.create "LeanRx-\"keyed\"").check with
    | .ok checked => pure checked
    | .error error => throw <| IO.userError error.code
  let emitted ← match Backend.JsFrameworkBenchmark.emit "LeanRx.mjs" checked with
    | .ok emitted => pure emitted
    | .error error => throw <| IO.userError s!"{error.code}: {error.message}"
  assertEq #["mount"] emitted.manifest.exports
  assertEq 8 emitted.manifest.eventCount
  assertEq 14 emitted.manifest.runtimeAbi
  assertEq #["./leanrx_dom.mjs", "./leanrx_region.mjs"]
    emitted.manifest.hostImports
  unless emitted.manifest.features.contains "keyed-region" &&
      emitted.manifest.features.contains "benchmark-contract" &&
      ¬emitted.manifest.features.contains "structural-delta" do
    throw <| IO.userError "benchmark manifest lost the default keyed-only disclosure"
  let readable ← match Js.Printer.module .readable emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError error.code
  let compact ← match Js.Printer.module .compact emitted.module with
    | .ok source => pure source
    | .error error => throw <| IO.userError error.code
  unless readable.contains "createKeyedRegion" && readable.contains "data-lrx-action" &&
      readable.contains "runlots" && readable.contains "glyphicon-remove" &&
      readable.contains "10000" && ¬readable.contains "createDeltaKeyedRegion" &&
      compact.length < readable.length do
    throw <| IO.userError "benchmark printer output lost the upstream keyed table lowering"
  -- The model rows are the keyed items (no per-commit projection array), the
  -- region forwards the mount-local context to the row callbacks, and a
  -- selection change re-runs exactly two retained rows through `updateAt`.
  unless readable.contains "[\"updateAt\"]" && readable.contains "$lrx_benchmarkCommitRows" &&
      ¬readable.contains "$lrx_benchmarkProject" &&
      readable.contains "[\"update\"](state[0], context)" do
    throw <| IO.userError "benchmark lowering lost the context-forwarding keyed commit"
  -- A swap exchanges exactly the two model positions through `swapAt` and a
  -- removal disposes exactly the found row through `removeAt` (ADR-0026);
  -- neither reconciles the whole row list.
  unless readable.contains "[\"swapAt\"](first, second, state[0], context)" &&
      readable.contains "$lrx_benchmarkCommitSwap(state, context, 1, 998, \"swaprows\")" &&
      readable.contains "[\"removeAt\"](index, key, context)" &&
      readable.contains "$lrx_benchmarkCommitRemove(state, context, foundIndex, parsedKey, \"remove\")" do
    throw <| IO.userError "benchmark lowering lost the targeted swap/remove commits"

end LeanRxTest.Backend.JsFrameworkBenchmark
