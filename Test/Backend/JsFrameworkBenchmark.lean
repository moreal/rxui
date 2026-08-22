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
  assertEq 8 emitted.manifest.runtimeAbi
  assertEq #["./leanrx_dom.mjs", "./leanrx_region.mjs", "./leanrx_host.mjs"]
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

end LeanRxTest.Backend.JsFrameworkBenchmark
