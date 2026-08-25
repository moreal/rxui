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
  assertEq 16 emitted.manifest.runtimeAbi
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
  unless readable.contains "createKeyedRegion" && readable.contains "runlots" &&
      readable.contains "glyphicon-remove" &&
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
  -- Row ids are safe integers (ADR-0029): the model's next id starts at the
  -- Number 1, a delegated key is parsed with `Number`, no BigInt reaches the
  -- module, and the manifest discloses the representation.
  unless readable.contains "[rows, 1, null]" && readable.contains "Number(key)" &&
      ¬readable.contains "BigInt" && ¬readable.contains "1n" &&
      emitted.manifest.features.contains "safe-integer-ids" do
    throw <| IO.userError "benchmark lowering lost the safe-integer id representation"
  -- Row clicks are resolved by structure (ADR-0030): the table body's listener
  -- maps the clicked cell's position to its action and the cloned rows carry
  -- no action attribute; the buttons go through the same listener on the
  -- page's `#buttons` row (ADR-0032), so the attribute adapter is not imported.
  unless readable.contains "listenDelegatedCells(tbody, \"click\", state, context, $lrx_benchmarkDispatch, [\"\", \"select\", \"remove\", \"\"])" &&
      ¬readable.contains "data-lrx-action" do
    throw <| IO.userError "benchmark lowering lost the structural row-click delegation"
  unless readable.contains "setKey(buttons, \"\")" &&
      readable.contains "listenDelegatedCells(buttons, \"click\", state, context, $lrx_benchmarkDispatch, [\"run\", \"runlots\", \"add\", \"update\", \"clear\", \"swaprows\"])" &&
      ¬readable.contains "listenDelegated(" &&
      Backend.JsFrameworkBenchmark.buttonActions == ["run", "runlots", "add", "update", "clear", "swaprows"] do
    throw <| IO.userError "benchmark lowering lost the structural button delegation"

end LeanRxTest.Backend.JsFrameworkBenchmark
